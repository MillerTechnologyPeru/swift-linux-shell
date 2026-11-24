//
//  StatusItems.swift
//  CacaoMenuBar
//

import CacaoSDL
import CacaoShellKit
import DBus
import Foundation

/// The status items other apps show in the menu bar, through the
/// StatusNotifierItem protocol on the session bus.
///
/// The menu bar serves the StatusNotifierWatcher, unless another process
/// already does, and reads the items as a host either way. Without a
/// session bus there are none.
@MainActor
final class StatusItems: ObservableObject {

    static let shared = StatusItems()

    /// The items to show: every registered item that isn't passive.
    @Published private(set) var items = [StatusItem]()

    private var host: StatusNotifierHost?

    private init() {
        Task { await run() }
    }

    func activate(_ item: StatusItem) {
        guard let host else { return }
        Task {
            do {
                try await host.activate(item)
            } catch {
                print("[CacaoMenuBar] \(item.displayName) didn't activate: \(error)")
            }
        }
    }

    private func run() async {
        do {
            let connection = try await DBusConnection.connect(to: .session)
            let watcher = StatusNotifierWatcher(connection: connection)
            if try await !watcher.start() {
                print("[CacaoMenuBar] Another process is the status item watcher; reading its items")
            }
            let host = StatusNotifierHost(connection: connection)
            self.host = host
            for await items in try await host.start() {
                self.items = items.filter { $0.status != .passive }
            }
        } catch {
            print("[CacaoMenuBar] Status items aren't available: \(error)")
        }
    }
}
