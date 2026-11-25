//
//  StatusItems.swift
//  CacaoMenuBar
//

import CacaoDBusMenu
import CacaoSDL
import CacaoShellKit
import DBus
import Foundation

/// The status items other apps show in the menu bar, through the
/// StatusNotifierItem protocol on the session bus, with their menus.
///
/// The menu bar serves the StatusNotifierWatcher, unless another process
/// already does, and reads the items as a host either way. An item's menu
/// is read over `com.canonical.dbusmenu` while the item has one. Without a
/// session bus there are none.
@MainActor
final class StatusItems: ObservableObject {

    static let shared = StatusItems()

    /// The items to show: every registered item that isn't passive.
    @Published private(set) var items = [StatusItem]()

    /// The items' menus, by item, as read.
    @Published private(set) var menus = [StatusItem.ID: DBusMenuItem]()

    private var host: StatusNotifierHost?

    private var connection: DBusConnection?

    /// A reader for each item with a menu, and where it reads.
    private var readers = [StatusItem.ID: (path: DBusObjectPath, reader: DBusMenuReader, following: Task<Void, Never>)]()

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

    // MARK: Menus

    /// An item's menu as its app serves it: told which item is chosen,
    /// and when the menu and its submenus open and close.
    func source(for item: StatusItem) -> MenuSource {
        let id = item.id
        return MenuSource { [weak self] menuItem in
            guard let reader = self?.readers[id]?.reader else { return }
            Task {
                do {
                    try await reader.click(menuItem.id)
                } catch {
                    print("[CacaoMenuBar] \(menuItem.title) wasn't chosen: \(error)")
                }
            }
        } willOpen: { [weak self] menu in
            guard let reader = self?.readers[id]?.reader else { return }
            Task {
                _ = try? await reader.aboutToShow(menu.id)
                try? await reader.opened(menu.id)
            }
        } didClose: { [weak self] menu in
            guard let reader = self?.readers[id]?.reader else { return }
            Task { try? await reader.closed(menu.id) }
        }
    }

    /// Reads the menus of items that have one, and stops reading the rest.
    private func followMenus() {
        guard let connection else { return }
        let wanted = Dictionary(items.compactMap { item in item.menu.map { (item.id, (item, $0)) } }) { first, _ in first }
        for (id, following) in readers where wanted[id]?.1 != following.path {
            following.following.cancel()
            readers[id] = nil
            menus[id] = nil
            Task { await following.reader.stop() }
        }
        for (id, (item, path)) in wanted where readers[id] == nil {
            let reader = DBusMenuReader(connection: connection, service: item.busName, path: path)
            let following = Task { [weak self] in
                do {
                    try await reader.start()
                } catch {
                    print("[CacaoMenuBar] Couldn't read the menu of \(item.displayName): \(error)")
                    return
                }
                guard !Task.isCancelled else { return }
                self?.menus[id] = await reader.menu
                for await menu in reader.changes {
                    guard !Task.isCancelled else { break }
                    self?.menus[id] = menu
                }
            }
            readers[id] = (path, reader, following)
        }
    }

    // MARK: Items

    private func run() async {
        do {
            let connection = try await DBusConnection.connect(to: .session)
            self.connection = connection
            let watcher = StatusNotifierWatcher(connection: connection)
            if try await !watcher.start() {
                print("[CacaoMenuBar] Another process is the status item watcher; reading its items")
            }
            let host = StatusNotifierHost(connection: connection)
            self.host = host
            for await items in try await host.start() {
                self.items = items.filter { $0.status != .passive }
                followMenus()
            }
        } catch {
            print("[CacaoMenuBar] Status items aren't available: \(error)")
        }
    }
}
