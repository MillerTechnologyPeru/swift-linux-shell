//
//  StatusNotifierWatcher.swift
//  CacaoShellKit
//

import DBus

/// The StatusNotifierWatcher: the registry status items announce themselves
/// to and the menu bar reads them from. The menu bar runs one, unless
/// another process already owns the name.
///
/// Items register with either their bus name, and serve
/// `/StatusNotifierItem`, or with their object path, and are found on the
/// caller's connection, as libappindicator's do. Each is named by its bus
/// name and path run together, as KDE's watcher names them, such as
/// `:1.42/StatusNotifierItem`. An item goes away when its bus name loses
/// its owner.
public actor StatusNotifierWatcher {

    /// The version of the StatusNotifierItem specification served.
    public static let protocolVersion: Int32 = 0

    public let connection: DBusConnection

    /// The registered items, in the order they registered.
    public private(set) var items = [String]()

    /// The bus names of the registered hosts.
    public private(set) var hosts = [String]()

    private var ownerChanges: Task<Void, Never>?

    public init(connection: DBusConnection) {
        self.connection = connection
    }

    /// Serves the watcher and asks for its name.
    ///
    /// - Returns: Whether this process now owns the name. If another process
    ///   does, nothing is served and that watcher should be used instead.
    @discardableResult
    public func start() async throws -> Bool {
        let changes = try await connection.signals(
            interface: DBusWellKnown.busInterface,
            member: Self.member("NameOwnerChanged"),
            sender: DBusWellKnown.busName
        )
        await connection.export(DBusExportedObject([implementation()]), at: ShellDBus.statusNotifierWatcherPath)
        let result = try await connection.requestName(ShellDBus.statusNotifierWatcherName)
        guard result == .primaryOwner || result == .alreadyOwner else {
            await connection.unexport(at: ShellDBus.statusNotifierWatcherPath)
            return false
        }
        ownerChanges = Task { [weak self] in
            for await message in changes {
                guard message.arguments.count == 3,
                      case let .string(name) = message.arguments[0],
                      case let .string(newOwner) = message.arguments[2],
                      newOwner.isEmpty
                else { continue }
                await self?.nameLost(name)
            }
        }
        return true
    }

    /// Stops following bus names. The watcher's object stays exported until
    /// the connection closes.
    public func stop() {
        ownerChanges?.cancel()
        ownerChanges = nil
    }

    // MARK: Registration

    /// The item's name for a registration, or nil if the argument is neither
    /// a bus name nor an object path.
    static func itemName(service: String, sender: String?) -> String? {
        if service.hasPrefix("/") {
            guard let sender, DBusObjectPath(rawValue: service) != nil else { return nil }
            return sender + service
        }
        guard DBusBusName(rawValue: service) != nil else { return nil }
        return service + "/StatusNotifierItem"
    }

    /// Splits an item's name into its bus name and object path.
    public static func split(_ item: String) -> (busName: DBusBusName, path: DBusObjectPath)? {
        guard let slash = item.firstIndex(of: "/"),
              let busName = DBusBusName(rawValue: String(item[..<slash])),
              let path = DBusObjectPath(rawValue: String(item[slash...]))
        else { return nil }
        return (busName, path)
    }

    private func registerItem(_ service: String, sender: String?) async throws {
        guard let item = Self.itemName(service: service, sender: sender) else {
            throw DBusError(name: .invalidArguments, message: "\(service) is neither a bus name nor an object path")
        }
        guard !items.contains(item) else { return }
        items.append(item)
        try await emit("StatusNotifierItemRegistered", [.string(item)])
    }

    private func registerHost(_ service: String) async throws {
        guard !hosts.contains(service) else { return }
        hosts.append(service)
        try await emit("StatusNotifierHostRegistered", [])
    }

    private func nameLost(_ name: String) async {
        let lost = items.filter { $0.hasPrefix(name + "/") }
        items.removeAll { lost.contains($0) }
        for item in lost {
            try? await emit("StatusNotifierItemUnregistered", [.string(item)])
        }
        if hosts.contains(name) {
            hosts.removeAll { $0 == name }
            try? await emit("StatusNotifierHostUnregistered", [])
        }
    }

    private func emit(_ name: String, _ arguments: [DBusMessageArgument]) async throws {
        let signal = DBusMessage.Signal(
            path: ShellDBus.statusNotifierWatcherPath,
            interface: ShellDBus.statusNotifierWatcherInterface,
            name: Self.member(name)
        )
        try await connection.emit(signal, arguments: arguments)
    }

    private static func member(_ name: String) -> DBusMember {
        DBusMember(rawValue: name)!
    }

    // MARK: D-Bus

    private func implementation() -> DBusInterfaceImplementation {
        DBusInterfaceImplementation(
            name: ShellDBus.statusNotifierWatcherInterface,
            methods: [
                .init(
                    name: Self.member("RegisterStatusNotifierItem"),
                    inputSignature: DBusSignature(rawValue: "s")!,
                    inputNames: ["service"]
                ) { [weak self] call in
                    guard case let .string(service)? = call.arguments.first else {
                        throw DBusError(name: .invalidArguments, message: "Expected a service")
                    }
                    try await self?.registerItem(service, sender: call.sender?.rawValue)
                    return []
                },
                .init(
                    name: Self.member("RegisterStatusNotifierHost"),
                    inputSignature: DBusSignature(rawValue: "s")!,
                    inputNames: ["service"]
                ) { [weak self] call in
                    guard case let .string(service)? = call.arguments.first else {
                        throw DBusError(name: .invalidArguments, message: "Expected a service")
                    }
                    try await self?.registerHost(service)
                    return []
                },
            ],
            properties: [
                .init(name: "RegisteredStatusNotifierItems", type: .array(.string)) { [weak self] in
                    let items = await self?.items ?? []
                    return .array(DBusMessageArgument.Array(type: .string, items.map { .string($0) })!)
                },
                .init(name: "IsStatusNotifierHostRegistered", type: .boolean) { [weak self] in
                    .boolean(!(await self?.hosts ?? []).isEmpty)
                },
                .init(name: "ProtocolVersion", type: .int32) {
                    .int32(Self.protocolVersion)
                },
            ],
            signals: [
                .init(name: Self.member("StatusNotifierItemRegistered"), signature: DBusSignature(rawValue: "s")!, argumentNames: ["service"]),
                .init(name: Self.member("StatusNotifierItemUnregistered"), signature: DBusSignature(rawValue: "s")!, argumentNames: ["service"]),
                .init(name: Self.member("StatusNotifierHostRegistered")),
                .init(name: Self.member("StatusNotifierHostUnregistered")),
            ]
        )
    }
}
