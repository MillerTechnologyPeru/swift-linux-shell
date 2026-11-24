//
//  AppMenus.swift
//  CacaoMenuBar
//

import CacaoDBusMenu
import CacaoSDL
import CacaoShellKit
import DBus
import Foundation

/// The focused app's menus, read from its `com.canonical.dbusmenu` object.
///
/// Until the compositor reports each window's menu address, an app's menu
/// is found by its `app_id`, at the bus name Cacao's `AppMenuDiscovery`
/// documents (`org.pureswift.Cacao.AppMenu.<escaped app_id>`, path
/// `/MenuBar`), which Cacao apps and Perry own. Apps that serve no menu
/// get the default app menu.
///
/// The menu bar also owns `com.canonical.AppMenu.Registrar`, which apps
/// check to know a global menu bar shows their menus.
///
/// The bar opens each menu with Cacao's `Menu`, as a popup surface of its
/// layer surface; choosing an item sends the app a click.
@MainActor
final class AppMenus: ObservableObject {

    static let shared = AppMenus()

    /// The focused app's `app_id`, or nil with no window focused.
    @Published private(set) var appID: String?

    /// The focused app's name, as its desktop entry gives it.
    @Published private(set) var appName: String?

    /// The menus of the bar: the app's menu's visible top-level items. Empty
    /// for an app that serves no menu.
    @Published private(set) var menus = [DBusMenuItem]()

    /// The app's own application menu: its first menu, when that's titled
    /// with the app's name, as Cacao apps' and Mac apps' are. Qt apps' menus
    /// start with File, so they get the default one.
    var appMenu: DBusMenuItem? {
        guard let first = menus.first, let appID else { return nil }
        let names = [appName, appID.split(separator: ".").last.map(String.init)].compactMap { $0?.lowercased() }
        return names.contains(first.title.lowercased()) ? first : nil
    }

    /// The menus after the application menu.
    var otherMenus: [DBusMenuItem] {
        appMenu == nil ? menus : Array(menus.dropFirst())
    }

    private var connection: DBusConnection?

    private var reader: DBusMenuReader?

    /// Follows the focused app's menu, replaced when focus moves.
    private var following: Task<Void, Never>?

    /// Every installed app, for naming the focused one.
    private let installed = DesktopEntry.installed()

    private init() {
        Task { await connect() }
    }

    // MARK: Menus

    /// Sends the app a click on an item, as when it's chosen from a menu.
    func click(_ item: DBusMenuItem) {
        guard let reader else { return }
        Task {
            do {
                try await reader.click(item.id)
            } catch {
                print("[CacaoMenuBar] \(item.title) wasn't chosen: \(error)")
            }
        }
    }

    /// Tells the app a menu is opening, so it can bring its items up to
    /// date; changes arrive through the reader and update the open menu.
    func willOpen(_ menu: DBusMenuItem) {
        guard let reader else { return }
        Task {
            _ = try? await reader.aboutToShow(menu.id)
            try? await reader.opened(menu.id)
        }
    }

    /// Tells the app a menu closed.
    func didClose(_ menu: DBusMenuItem) {
        guard let reader else { return }
        Task { try? await reader.closed(menu.id) }
    }

    // MARK: Following focus

    private func connect() async {
        do {
            let connection = try await DBusConnection.connect(to: .session)
            self.connection = connection
            if try await !AppMenuRegistrar(connection: connection).start() {
                print("[CacaoMenuBar] Another process is the menu registrar")
            }
            // Re-read when an app's menu name changes owner: an app started
            // serving its menu after it took focus, or quit.
            let owners = try await connection.signals(
                interface: DBusWellKnown.busInterface,
                member: DBusMember(rawValue: "NameOwnerChanged")!,
                sender: DBusWellKnown.busName
            )
            Task { [weak self] in
                for await message in owners {
                    guard case let .string(name)? = message.arguments.first,
                          let busName = DBusBusName(rawValue: name),
                          let appID = AppMenuDiscovery.appID(forBusName: busName)
                    else { continue }
                    await self?.menuNameChanged(appID: appID)
                }
            }
        } catch {
            print("[CacaoMenuBar] Apps' menus aren't available: \(error)")
        }
        let focused = FocusedApp.shared
        focused.onChange = { [weak self] appID in
            self?.focusChanged(to: appID)
        }
        focusChanged(to: focused.appID)
    }

    private func menuNameChanged(appID: String) {
        guard appID == self.appID else { return }
        follow(appID)
    }

    private func focusChanged(to appID: String?) {
        guard appID != self.appID else { return }
        self.appID = appID
        appName = appID.map(name(of:))
        follow(appID)
    }

    private func follow(_ appID: String?) {
        following?.cancel()
        let previous = reader
        reader = nil
        menus = []
        Task { await previous?.stop() }
        guard let appID, let connection else { return }
        following = Task { [weak self] in
            guard let reader = await AppMenuDiscovery.reader(forAppID: appID, on: connection) else {
                return
            }
            do {
                try await reader.start()
            } catch {
                print("[CacaoMenuBar] Couldn't read the menu of \(appID): \(error)")
                return
            }
            guard !Task.isCancelled, let self else {
                await reader.stop()
                return
            }
            self.reader = reader
            self.menus = Self.barMenus(of: await reader.menu)
            for await menu in reader.changes {
                guard !Task.isCancelled else { break }
                self.menus = Self.barMenus(of: menu)
            }
        }
    }

    private static func barMenus(of root: DBusMenuItem) -> [DBusMenuItem] {
        root.children.filter { $0.isVisible && $0.type == .standard }
    }

    /// An app's name: its desktop entry's, else the last part of its app_id.
    private func name(of appID: String) -> String {
        installed.first { $0.matches(appID: appID) }?.name
            ?? appID.split(separator: ".").last.map(String.init)
            ?? appID
    }
}
