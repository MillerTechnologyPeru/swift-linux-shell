//
//  LauncherEntries.swift
//  CacaoShellKit
//

import DBus

/// What an app asked its launcher to show, through
/// `com.canonical.Unity.LauncherEntry`: a count badge, a progress bar,
/// urgency and a menu.
public struct LauncherEntryState: Equatable, Sendable {

    public var count: Int64 = 0

    public var isCountVisible = false

    /// From 0 to 1.
    public var progress: Double = 0

    public var isProgressVisible = false

    /// The app wants attention.
    public var isUrgent = false

    /// A `com.canonical.dbusmenu` object for the launcher's menu, on the
    /// app's connection.
    public var quicklist: DBusObjectPath?

    public init() { }

    /// The badge's text, or nil when the app shows none.
    public var badge: String? {
        guard isCountVisible else { return nil }
        return count > 999 ? "999+" : String(count)
    }

    /// Whether there's anything to show.
    public var isEmpty: Bool {
        badge == nil && !isProgressVisible && !isUrgent
    }

    /// Takes the properties an `Update` signal carries. Each update changes
    /// only the properties it names.
    public mutating func apply(_ properties: DBusMessageArgument.Dictionary) {
        for entry in properties {
            guard let key = entry.key.stringValue else { continue }
            var value = entry.value
            if case let .variant(variant) = value {
                value = variant.element
            }
            switch (key, value) {
            case let ("count", .int64(count)):
                self.count = count
            case let ("count", .int32(count)):
                self.count = Int64(count)
            case let ("count", .uint32(count)):
                self.count = Int64(count)
            case let ("count-visible", .boolean(visible)):
                isCountVisible = visible
            case let ("progress", .double(progress)):
                self.progress = min(max(progress, 0), 1)
            case let ("progress-visible", .boolean(visible)):
                isProgressVisible = visible
            case let ("urgent", .boolean(urgent)):
                isUrgent = urgent
            case let ("quicklist", .string(path)):
                quicklist = DBusObjectPath(rawValue: path)
            case let ("quicklist", .objectPath(path)):
                quicklist = path
            default:
                break
            }
        }
    }
}

/// Follows apps' launcher entries for the dock: badges, progress and
/// urgency, by the desktop file ID of the app they're for.
///
/// Apps emit `com.canonical.Unity.LauncherEntry.Update` from any object
/// path, with their `application://<id>.desktop` URI. An app's entries go
/// away when it leaves the bus, so a badge never outlives its app.
public actor LauncherEntries {

    public let connection: DBusConnection

    /// Each app's state, by desktop file ID.
    public private(set) var entries = [String: LauncherEntryState]()

    /// The connection each entry came from.
    private var senders = [String: String]()

    private var continuation: AsyncStream<[String: LauncherEntryState]>.Continuation?

    private var following: [Task<Void, Never>] = []

    public init(connection: DBusConnection) {
        self.connection = connection
    }

    /// Starts following entries.
    ///
    /// - Returns: Every entry after each change, starting with the current
    ///   ones.
    public func start() async throws -> AsyncStream<[String: LauncherEntryState]> {
        let updates = try await connection.signals(
            interface: ShellDBus.launcherEntryInterface,
            member: DBusMember(rawValue: "Update")!
        )
        let owners = try await connection.signals(
            interface: DBusWellKnown.busInterface,
            member: DBusMember(rawValue: "NameOwnerChanged")!,
            sender: DBusWellKnown.busName
        )
        let (stream, continuation) = AsyncStream.makeStream(of: [String: LauncherEntryState].self)
        self.continuation = continuation
        continuation.yield(entries)
        following = [
            Task { [weak self] in
                for await message in updates {
                    await self?.update(message)
                }
            },
            Task { [weak self] in
                for await message in owners {
                    guard message.arguments.count == 3,
                          case let .string(name) = message.arguments[0],
                          case let .string(newOwner) = message.arguments[2],
                          newOwner.isEmpty
                    else { continue }
                    await self?.left(name)
                }
            },
        ]
        return stream
    }

    public func stop() {
        following.forEach { $0.cancel() }
        following = []
        continuation?.finish()
        continuation = nil
    }

    /// The desktop file ID in an `application://` URI: `firefox` for
    /// `application://firefox.desktop`.
    public static func desktopID(appURI: String) -> String? {
        let prefix = "application://"
        guard appURI.hasPrefix(prefix) else { return nil }
        var id = String(appURI.dropFirst(prefix.count))
        if id.hasSuffix(".desktop") {
            id.removeLast(".desktop".count)
        }
        return id.isEmpty ? nil : id
    }

    private func update(_ message: DBusMessage) {
        guard message.arguments.count == 2,
              case let .string(uri) = message.arguments[0],
              case let .dictionary(properties) = message.arguments[1],
              let id = Self.desktopID(appURI: uri)
        else { return }
        var state = entries[id] ?? LauncherEntryState()
        state.apply(properties)
        entries[id] = state
        if let sender = message.sender?.rawValue {
            senders[id] = sender
        }
        continuation?.yield(entries)
    }

    /// An app left the bus: its entries go.
    private func left(_ name: String) {
        let gone = senders.filter { $0.value == name }.map(\.key)
        guard !gone.isEmpty else { return }
        for id in gone {
            entries[id] = nil
            senders[id] = nil
        }
        continuation?.yield(entries)
    }
}
