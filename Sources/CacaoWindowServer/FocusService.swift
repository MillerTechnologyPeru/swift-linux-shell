//
//  FocusService.swift
//  CacaoWindowServer
//

import CacaoShellKit
import DBus

/// Tells the shell which window has focus, on the session bus, as
/// `org.pureswift.Cacao.WindowServer1`: the menu bar shows that window's
/// menus.
///
/// The event loop keeps the main thread, so the service runs on its own:
/// `update` hands it each change, in order, and returns at once.
final class FocusService: Sendable {

    private let updates: AsyncStream<FocusedWindow?>.Continuation

    init() {
        // Only the latest focus matters to a menu bar that falls behind.
        let (stream, continuation) = AsyncStream.makeStream(
            of: FocusedWindow?.self,
            bufferingPolicy: .bufferingNewest(1)
        )
        updates = continuation
        Task.detached {
            await Self.serve(stream)
        }
    }

    /// Tells the shell focus moved to a window, or to none.
    func update(_ window: FocusedWindow?) {
        updates.yield(window)
    }

    private static func serve(_ updates: AsyncStream<FocusedWindow?>) async {
        let connection: DBusConnection
        do {
            connection = try await DBusConnection.connect(to: .session)
        } catch {
            log("No session bus, so the menu bar can't follow focus: \(error)")
            return
        }
        let current = Current()
        await connection.export(DBusExportedObject([interface(current)]), at: ShellDBus.windowServerPath)
        do {
            let result = try await connection.requestName(ShellDBus.windowServerName)
            if result != .primaryOwner {
                log("Another process owns \(ShellDBus.windowServerName.rawValue)")
            }
        } catch {
            log("Could not own \(ShellDBus.windowServerName.rawValue): \(error)")
        }
        for await window in updates {
            guard await current.set(window) else { continue }
            do {
                try await connection.emit(
                    FocusedWindow.focusChangedSignal,
                    arguments: FocusedWindow.arguments(for: window)
                )
            } catch {
                log("Could not emit FocusChanged: \(error)")
            }
        }
    }

    private static func interface(_ current: Current) -> DBusInterfaceImplementation {
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
            ],
            signals: [
                .init(
                    name: FocusedWindow.focusChanged,
                    signature: FocusedWindow.signature,
                    argumentNames: FocusedWindow.argumentNames
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
