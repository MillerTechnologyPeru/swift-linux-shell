//
//  WindowServerService.swift
//  CacaoWindowServer
//

import CacaoShellKit
import DBus
import Foundation

/// The window server's interface to the shell on the session bus,
/// `org.pureswift.Cacao.WindowServer1`: which window has focus, for the
/// menu bar to show its menus, and the session's actions, Log Out and
/// Force Quit.
///
/// The event loop keeps the main thread, so the service runs on its own.
/// `update` and `request` hand it changes, in order, and return at once.
/// Calls the shell makes come back to the main thread through `perform`,
/// which wakes the event loop.
final class WindowServerService: Sendable {

    /// What the service sends to the shell.
    private enum Event: Sendable {
        case focus(FocusedWindow?)
        case action(WindowServerActions.Action)
    }

    /// What the shell asked for.
    enum Call: Sendable {
        case logOut
        case forceQuit(appID: String)
    }

    private let events: AsyncStream<Event>.Continuation

    /// Runs a call from the shell on the main thread.
    private let perform: @Sendable (Call) -> Void

    init(perform: @escaping @Sendable (Call) -> Void) {
        let (stream, continuation) = AsyncStream.makeStream(of: Event.self)
        events = continuation
        self.perform = perform
        Task.detached { [perform] in
            await Self.serve(stream, perform: perform)
        }
    }

    /// Tells the shell focus moved to a window, or to none.
    func update(_ window: FocusedWindow?) {
        events.yield(.focus(window))
    }

    /// Asks the shell to show an action's dialog.
    func request(_ action: WindowServerActions.Action) {
        events.yield(.action(action))
    }

    private static func serve(_ events: AsyncStream<Event>, perform: @escaping @Sendable (Call) -> Void) async {
        let connection: DBusConnection
        do {
            connection = try await DBusConnection.connect(to: .session)
        } catch {
            log("No session bus, so the menu bar can't follow focus: \(error)")
            return
        }
        let current = Current()
        await connection.export(DBusExportedObject([interface(current, perform: perform)]), at: ShellDBus.windowServerPath)
        do {
            let result = try await connection.requestName(ShellDBus.windowServerName)
            if result != .primaryOwner {
                log("Another process owns \(ShellDBus.windowServerName.rawValue)")
            }
        } catch {
            log("Could not own \(ShellDBus.windowServerName.rawValue): \(error)")
        }
        for await event in events {
            do {
                switch event {
                case let .focus(window):
                    guard await current.set(window) else { continue }
                    try await connection.emit(
                        FocusedWindow.focusChangedSignal,
                        arguments: FocusedWindow.arguments(for: window)
                    )
                case let .action(action):
                    try await connection.emit(
                        WindowServerActions.actionRequestedSignal,
                        arguments: [.string(action.rawValue)]
                    )
                }
            } catch {
                log("Could not tell the shell: \(error)")
            }
        }
    }

    private static func interface(_ current: Current, perform: @escaping @Sendable (Call) -> Void) -> DBusInterfaceImplementation {
        DBusInterfaceImplementation(
            name: ShellDBus.windowServerInterface,
            methods: [
                .init(
                    name: FocusedWindow.getFocusedWindow,
                    outputSignature: FocusedWindow.signature,
                    outputNames: FocusedWindow.argumentNames
                ) { _ in
                    FocusedWindow.arguments(for: await current.window)
                },
                .init(name: WindowServerActions.logOut) { _ in
                    perform(.logOut)
                    return []
                },
                .init(
                    name: WindowServerActions.forceQuit,
                    inputSignature: DBusSignature(rawValue: "s")!,
                    inputNames: ["app_id"]
                ) { call in
                    guard case let .string(appID)? = call.arguments.first else { return [] }
                    perform(.forceQuit(appID: appID))
                    return []
                },
            ],
            signals: [
                .init(
                    name: FocusedWindow.focusChanged,
                    signature: FocusedWindow.signature,
                    argumentNames: FocusedWindow.argumentNames
                ),
                .init(
                    name: WindowServerActions.actionRequested,
                    signature: DBusSignature(rawValue: "s")!,
                    argumentNames: ["action"]
                ),
            ]
        )
    }

    /// The focused window, for the method to answer with.
    private actor Current {

        private(set) var window: FocusedWindow?

        /// Records a change; false when it's the same as before.
        func set(_ window: FocusedWindow?) -> Bool {
            guard window != self.window else { return false }
            self.window = window
            return true
        }
    }
}

/// Work for the main thread from other threads, run when the event loop
/// wakes (`cwl_server_wake`).
final class MainThreadQueue: @unchecked Sendable {

    private let lock = NSLock()

    private var work: [@Sendable @MainActor () -> Void] = []

    /// Wakes the event loop; set once the server exists.
    private var wake: (@Sendable () -> Void)?

    func setWake(_ wake: @escaping @Sendable () -> Void) {
        lock.lock()
        self.wake = wake
        lock.unlock()
    }

    /// Runs `body` on the main thread soon.
    func async(_ body: @escaping @Sendable @MainActor () -> Void) {
        lock.lock()
        work.append(body)
        let wake = self.wake
        lock.unlock()
        wake?()
    }

    /// Runs what's queued: on the main thread, when the event loop wakes.
    @MainActor
    func drain() {
        lock.lock()
        let pending = work
        work = []
        lock.unlock()
        for body in pending {
            body()
        }
    }
}
