//
//  AppMenuRegistrar.swift
//  CacaoShellKit
//

import DBus

/// `com.canonical.AppMenu.Registrar`: where X11 apps register the dbusmenu
/// of each of their windows.
///
/// The menu bar serves it mainly as a signal. Qt apps, Perry and Cacao
/// apps hide their own menu bar while the name has an owner, because a
/// global menu bar shows their menus. Wayland apps tie menus to windows
/// with the appmenu protocol instead, so the registrations are only kept
/// for the X11 apps that will come with XWayland.
public actor AppMenuRegistrar {

    /// A window's registered menu.
    public struct Registration: Equatable, Sendable {
        public var service: DBusBusName
        public var path: DBusObjectPath
    }

    public let connection: DBusConnection

    /// The registered menus, by X11 window ID.
    public private(set) var windows = [UInt32: Registration]()

    private var ownerChanges: Task<Void, Never>?

    public init(connection: DBusConnection) {
        self.connection = connection
    }

    /// Serves the registrar and asks for its name.
    ///
    /// - Returns: Whether this process now owns the name. If another process
    ///   does, nothing is served.
    @discardableResult
    public func start() async throws -> Bool {
        let changes = try await connection.signals(
            interface: DBusWellKnown.busInterface,
            member: Self.member("NameOwnerChanged"),
            sender: DBusWellKnown.busName
        )
        await connection.export(DBusExportedObject([implementation()]), at: ShellDBus.appMenuRegistrarPath)
        let result = try await connection.requestName(ShellDBus.appMenuRegistrarName)
        guard result == .primaryOwner || result == .alreadyOwner else {
            await connection.unexport(at: ShellDBus.appMenuRegistrarPath)
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

    public func stop() {
        ownerChanges?.cancel()
        ownerChanges = nil
    }

    // MARK: Registrations

    private func register(window: UInt32, service: DBusBusName, path: DBusObjectPath) async {
        windows[window] = Registration(service: service, path: path)
        try? await emit("WindowRegistered", [.uint32(window), .string(service.rawValue), .objectPath(path)])
    }

    private func unregister(window: UInt32) async {
        guard windows.removeValue(forKey: window) != nil else { return }
        try? await emit("WindowUnregistered", [.uint32(window)])
    }

    private func registration(for window: UInt32) throws -> Registration {
        guard let registration = windows[window] else {
            throw DBusError(name: .invalidArguments, message: "Window \(window) has no registered menu")
        }
        return registration
    }

    private func nameLost(_ name: String) async {
        for (window, registration) in windows where registration.service.rawValue == name {
            await unregister(window: window)
        }
    }

    private func emit(_ name: String, _ arguments: [DBusMessageArgument]) async throws {
        let signal = DBusMessage.Signal(
            path: ShellDBus.appMenuRegistrarPath,
            interface: ShellDBus.appMenuRegistrarInterface,
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
            name: ShellDBus.appMenuRegistrarInterface,
            methods: [
                .init(
                    name: Self.member("RegisterWindow"),
                    inputSignature: DBusSignature(rawValue: "uo")!,
                    inputNames: ["windowId", "menuObjectPath"]
                ) { [weak self] call in
                    guard call.arguments.count == 2,
                          case let .uint32(window) = call.arguments[0],
                          case let .objectPath(path) = call.arguments[1],
                          let sender = call.sender
                    else {
                        throw DBusError(name: .invalidArguments, message: "Expected a window ID and an object path")
                    }
                    await self?.register(window: window, service: sender, path: path)
                    return []
                },
                .init(
                    name: Self.member("UnregisterWindow"),
                    inputSignature: DBusSignature(rawValue: "u")!,
                    inputNames: ["windowId"]
                ) { [weak self] call in
                    guard case let .uint32(window)? = call.arguments.first else {
                        throw DBusError(name: .invalidArguments, message: "Expected a window ID")
                    }
                    await self?.unregister(window: window)
                    return []
                },
                .init(
                    name: Self.member("GetMenuForWindow"),
                    inputSignature: DBusSignature(rawValue: "u")!,
                    outputSignature: DBusSignature(rawValue: "so")!,
                    inputNames: ["windowId"],
                    outputNames: ["service", "menuObjectPath"]
                ) { [weak self] call in
                    guard case let .uint32(window)? = call.arguments.first, let self else {
                        throw DBusError(name: .invalidArguments, message: "Expected a window ID")
                    }
                    let registration = try await self.registration(for: window)
                    return [.string(registration.service.rawValue), .objectPath(registration.path)]
                },
            ],
            signals: [
                .init(name: Self.member("WindowRegistered"), signature: DBusSignature(rawValue: "uso")!, argumentNames: ["windowId", "service", "menuObjectPath"]),
                .init(name: Self.member("WindowUnregistered"), signature: DBusSignature(rawValue: "u")!, argumentNames: ["windowId"]),
            ]
        )
    }
}
