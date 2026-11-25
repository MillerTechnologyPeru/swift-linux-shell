//
//  NotificationServer.swift
//  CacaoShellKit
//

import DBus

/// A notification an app posted, to show as a banner.
public struct DesktopNotification: Identifiable, Equatable, Sendable {

    public var id: UInt32

    /// The app's name, as it gives it.
    public var appName: String

    /// An icon name or `file://` URL, or empty.
    public var appIcon: String

    public var summary: String

    public var body: String

    /// The buttons, in order. The one keyed `default` is what clicking the
    /// banner does, and isn't shown as a button.
    public var actions: [Action]

    /// How long to show the banner, in milliseconds: -1 for the server's
    /// default, 0 for until it's closed.
    public var expireTimeout: Int32

    public var urgency: Urgency

    public struct Action: Equatable, Sendable {
        public var key: String
        public var label: String

        public init(key: String, label: String) {
            self.key = key
            self.label = label
        }
    }

    /// The `urgency` hint.
    public enum Urgency: UInt8, Sendable {
        case low = 0
        case normal = 1
        /// Stays until closed.
        case critical = 2
    }

    public init(
        id: UInt32,
        appName: String,
        appIcon: String = "",
        summary: String,
        body: String = "",
        actions: [Action] = [],
        expireTimeout: Int32 = -1,
        urgency: Urgency = .normal
    ) {
        self.id = id
        self.appName = appName
        self.appIcon = appIcon
        self.summary = summary
        self.body = body
        self.actions = actions
        self.expireTimeout = expireTimeout
        self.urgency = urgency
    }

    /// Whether clicking the banner does something.
    public var hasDefaultAction: Bool {
        actions.contains { $0.key == "default" }
    }

    /// The actions shown as buttons.
    public var buttons: [Action] {
        actions.filter { $0.key != "default" }
    }
}

/// Why a notification closed, as `NotificationClosed` gives it.
public enum NotificationCloseReason: UInt32, Sendable {
    case expired = 1
    /// The user dismissed it, or chose one of its actions.
    case dismissed = 2
    /// The app called `CloseNotification`.
    case closedByCall = 3
    case undefined = 4
}

/// The desktop's notification server, `org.freedesktop.Notifications`, as
/// the Desktop Notifications Specification 1.2 has it. The menu bar runs
/// one and shows its notifications as banners, unless another process
/// already owns the name.
///
/// The server keeps no UI of its own: `events` says what to show and when
/// to stop, and the UI calls `close` and `invoke` back.
public actor NotificationServer {

    /// What the UI is told.
    public enum Event: Sendable {
        /// A notification to show, or to show again in place of the one
        /// with the same `id`.
        case posted(DesktopNotification)
        /// A notification to stop showing.
        case closed(id: UInt32)
    }

    public let connection: DBusConnection

    public nonisolated let events: AsyncStream<Event>

    private let continuation: AsyncStream<Event>.Continuation

    /// The notifications not closed yet, by their IDs.
    public private(set) var open = Set<UInt32>()

    private var nextID: UInt32 = 1

    public init(connection: DBusConnection) {
        self.connection = connection
        (events, continuation) = AsyncStream.makeStream(of: Event.self)
    }

    /// Serves the interface and asks for its name.
    ///
    /// - Returns: Whether this process now owns the name. If another
    ///   process does, nothing is served.
    @discardableResult
    public func start() async throws -> Bool {
        await connection.export(DBusExportedObject([implementation()]), at: ShellDBus.notificationsPath)
        let result = try await connection.requestName(ShellDBus.notificationsName)
        guard result == .primaryOwner || result == .alreadyOwner else {
            await connection.unexport(at: ShellDBus.notificationsPath)
            return false
        }
        return true
    }

    // MARK: From the UI

    /// Closes a notification, and tells its app why.
    public func close(_ id: UInt32, reason: NotificationCloseReason) async {
        guard open.remove(id) != nil else { return }
        continuation.yield(.closed(id: id))
        try? await connection.emit(Self.notificationClosed, arguments: [.uint32(id), .uint32(reason.rawValue)])
    }

    /// The user chose one of a notification's actions, or clicked a banner
    /// with a default one. The notification closes, as dismissed.
    public func invoke(_ id: UInt32, action key: String) async {
        guard open.contains(id) else { return }
        try? await connection.emit(Self.actionInvoked, arguments: [.uint32(id), .string(key)])
        await close(id, reason: .dismissed)
    }

    // MARK: From apps

    /// Posts a notification from `Notify`'s arguments, and returns its ID.
    func post(_ arguments: [DBusMessageArgument]) throws -> UInt32 {
        guard arguments.count == 8,
              case let .string(appName) = arguments[0],
              case let .uint32(replacesID) = arguments[1],
              case let .string(appIcon) = arguments[2],
              case let .string(summary) = arguments[3],
              case let .string(body) = arguments[4],
              case let .array(actionList) = arguments[5],
              case let .int32(expireTimeout) = arguments[7]
        else {
            throw DBusError(name: .invalidArguments, message: "Notify takes susssasa{sv}i")
        }
        let id: UInt32
        if replacesID != 0, open.contains(replacesID) {
            id = replacesID
        } else {
            id = nextID
            nextID = nextID == .max ? 1 : nextID + 1
        }
        // Actions come as pairs: a key, then its label.
        let strings = actionList.compactMap(\.stringValue)
        var actions: [DesktopNotification.Action] = []
        var index = 0
        while index + 1 < strings.count {
            actions.append(.init(key: strings[index], label: strings[index + 1]))
            index += 2
        }
        var urgency = DesktopNotification.Urgency.normal
        if case let .dictionary(hints) = arguments[6] {
            for entry in hints {
                guard entry.key.stringValue == "urgency" else { continue }
                var value = entry.value
                if case let .variant(variant) = value {
                    value = variant.element
                }
                if case let .byte(byte) = value, let level = DesktopNotification.Urgency(rawValue: byte) {
                    urgency = level
                }
            }
        }
        let notification = DesktopNotification(
            id: id,
            appName: appName,
            appIcon: appIcon,
            summary: summary,
            body: body,
            actions: actions,
            expireTimeout: expireTimeout,
            urgency: urgency
        )
        open.insert(id)
        continuation.yield(.posted(notification))
        return id
    }

    // MARK: The interface

    static let notificationClosed = DBusMessage.Signal(
        path: ShellDBus.notificationsPath,
        interface: ShellDBus.notificationsInterface,
        name: DBusMember(rawValue: "NotificationClosed")!
    )

    static let actionInvoked = DBusMessage.Signal(
        path: ShellDBus.notificationsPath,
        interface: ShellDBus.notificationsInterface,
        name: DBusMember(rawValue: "ActionInvoked")!
    )

    /// What the server can show.
    static let capabilities = ["actions", "body"]

    private func implementation() -> DBusInterfaceImplementation {
        DBusInterfaceImplementation(
            name: ShellDBus.notificationsInterface,
            methods: [
                .init(
                    name: DBusMember(rawValue: "GetCapabilities")!,
                    outputSignature: DBusSignature(rawValue: "as")!,
                    outputNames: ["capabilities"]
                ) { _ in
                    [.array(DBusMessageArgument.Array(type: .string, Self.capabilities.map { .string($0) })!)]
                },
                .init(
                    name: DBusMember(rawValue: "Notify")!,
                    inputSignature: DBusSignature(rawValue: "susssasa{sv}i")!,
                    outputSignature: DBusSignature(rawValue: "u")!,
                    inputNames: ["app_name", "replaces_id", "app_icon", "summary", "body", "actions", "hints", "expire_timeout"],
                    outputNames: ["id"]
                ) { [weak self] call in
                    guard let self else { return [.uint32(0)] }
                    return [.uint32(try await self.post(call.arguments))]
                },
                .init(
                    name: DBusMember(rawValue: "CloseNotification")!,
                    inputSignature: DBusSignature(rawValue: "u")!,
                    inputNames: ["id"]
                ) { [weak self] call in
                    if case let .uint32(id)? = call.arguments.first {
                        await self?.close(id, reason: .closedByCall)
                    }
                    return []
                },
                .init(
                    name: DBusMember(rawValue: "GetServerInformation")!,
                    outputSignature: DBusSignature(rawValue: "ssss")!,
                    outputNames: ["name", "vendor", "version", "spec_version"]
                ) { _ in
                    [.string("Cacao"), .string("PureSwift"), .string("1.0"), .string("1.2")]
                },
            ],
            signals: [
                .init(
                    name: DBusMember(rawValue: "NotificationClosed")!,
                    signature: DBusSignature(rawValue: "uu")!,
                    argumentNames: ["id", "reason"]
                ),
                .init(
                    name: DBusMember(rawValue: "ActionInvoked")!,
                    signature: DBusSignature(rawValue: "us")!,
                    argumentNames: ["id", "action_key"]
                ),
            ]
        )
    }
}
