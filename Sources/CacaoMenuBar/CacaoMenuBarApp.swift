//
//  CacaoMenuBarApp.swift
//  CacaoMenuBar
//
//  The menu bar: the focused app's menus at the left, other apps' status
//  items and the clock at the right.
//
//  It sits in the top layer of the screen along the top edge, and windows
//  stay below it. It shows the focused app's name and its menus, read over
//  com.canonical.dbusmenu.
//

import CacaoDBusMenu
import CacaoSDL
import CacaoShellKit
import Foundation

@main
struct CacaoMenuBarApp: App {

    init() {
        // The Wayland app_id.
        SDLHost.appIdentifier = "org.pureswift.Cacao.MenuBar"
        // Its windows are the shell's, not an app's: no menus of its own.
        SDLHost.exportsMenus = false
    }

    var body: some Scene {
        WindowGroup("Menu Bar") {
            MenuBarView()
        }
        // The width is the screen's, from the anchors.
        .defaultSize(width: 1280, height: MenuBarView.height)
        .windowLayer(
            .top,
            edges: [.top, .leading, .trailing],
            exclusiveZone: MenuBarView.height,
            namespace: "cacao-menu-bar"
        )

        // The system menu's windows: in the middle of the screen, over
        // everything, and not among apps' windows, so neither the dock nor
        // the menu bar takes them for an app's.
        WindowGroup("Confirm", for: SessionAction.self) { $action in
            SessionConfirmation(action: action ?? .logOut)
        }
        .defaultSize(width: 420, height: 160)
        .windowLayer(.overlay, edges: [], keyboardInteractivity: .exclusive, namespace: "cacao-dialog")

        Window("Force Quit Applications", id: SystemActions.forceQuitWindowID) {
            ForceQuitView()
        }
        .defaultSize(width: 400, height: 320)
        .windowLayer(.overlay, edges: [], keyboardInteractivity: .exclusive, namespace: "cacao-dialog")

        // Apps' notifications, below the menu bar at the right; they
        // never take the keyboard.
        Window("Notification", id: Notifications.bannerWindowID) {
            NotificationBanner()
        }
        .defaultSize(width: 360, height: 120)
        .windowLayer(
            .overlay,
            edges: [.top, .trailing],
            margins: EdgeInsets(top: 8, leading: 0, bottom: 0, trailing: 12),
            keyboardInteractivity: .none,
            namespace: "cacao-notification"
        )

        Window("About This Computer", id: SystemActions.aboutWindowID) {
            AboutView()
        }
        .defaultSize(width: 320, height: 240)
        .windowLayer(.overlay, edges: [], keyboardInteractivity: .onDemand, namespace: "cacao-dialog")
    }
}

struct MenuBarView: View {

    static let height: CGFloat = 28

    @ObservedObject var appMenus = AppMenus.shared

    @Environment(\.openWindow) private var openWindow

    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        HStack(spacing: 8) {
            SystemMenu()
            HStack(spacing: 0) {
                // The app menu, in bold: the app's own when it serves one,
                // else the default one, or the desktop's with no window
                // focused.
                if let appMenu = appMenus.appMenu {
                    BarMenu(menu: appMenu, isAppMenu: true)
                } else if let appName = appMenus.appName {
                    DefaultAppMenu(appName: appName)
                } else {
                    Text("Desktop")
                        .fontWeight(.semibold)
                        .lineLimit(1)
                        .padding(.horizontal, 8)
                }
                ForEach(appMenus.otherMenus) { menu in
                    BarMenu(menu: menu, isAppMenu: false)
                }
            }
            .menuStyle(.borderlessButton)
            Spacer()
            StatusArea()
        }
        .font(.system(size: 13))
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, minHeight: Self.height, maxHeight: Self.height)
        .onAppear {
            // The menu bar shows apps' notifications.
            let notifications = Notifications.shared
            notifications.openWindow = openWindow
            notifications.dismissWindow = dismissWindow
            Task {
                await notifications.start()
            }
        }
    }
}

/// One of the app's menus in the bar. It opens below the bar as a popup.
struct BarMenu: View {

    let menu: DBusMenuItem

    let isAppMenu: Bool

    var body: some View {
        Menu {
            MenuItems(menu: menu)
        } label: {
            Text(menu.title)
                .fontWeight(isAppMenu ? .semibold : .regular)
                .lineLimit(1)
        }
        .disabled(!menu.isEnabled)
    }
}

/// The app a menu is read from: told which item is chosen, and when its
/// menus open and close.
struct MenuSource {

    let click: @MainActor (DBusMenuItem) -> Void

    let willOpen: @MainActor (DBusMenuItem) -> Void

    let didClose: @MainActor (DBusMenuItem) -> Void

    /// The focused app's menus.
    @MainActor
    static var appMenus: MenuSource {
        let menus = AppMenus.shared
        return MenuSource(click: menus.click, willOpen: menus.willOpen, didClose: menus.didClose)
    }
}

/// A menu's items: buttons, submenus and separators. Its content exists
/// only while the menu is open, so appearing tells the app it opened.
struct MenuItems: View {

    let menu: DBusMenuItem

    var source: MenuSource = .appMenus

    var body: some View {
        ForEach(menu.children.filter(\.isVisible)) { item in
            if item.type == .separator {
                Divider()
            } else if item.isSubmenu {
                Menu {
                    MenuItems(menu: item, source: source)
                } label: {
                    MenuItemLabel(item: item)
                }
                .disabled(!item.isEnabled)
            } else {
                Button {
                    source.click(item)
                } label: {
                    MenuItemLabel(item: item)
                }
                .disabled(!item.isEnabled)
            }
        }
        .onAppear { source.willOpen(menu) }
        .onDisappear { source.didClose(menu) }
    }
}

/// An item's title, with its checkmark or radio mark and its shortcut.
struct MenuItemLabel: View {

    let item: DBusMenuItem

    var body: some View {
        HStack(spacing: 6) {
            if item.toggleType != nil {
                Text(mark)
                    .frame(width: 12)
            }
            Text(item.title)
                .lineLimit(1)
            Spacer(minLength: 16)
            if let shortcut = item.shortcut {
                Text(shortcut.glyphs)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var mark: String {
        switch (item.toggleType, item.toggleState) {
        case (.checkmark?, .on): return "✓"
        case (.radio?, .on): return "•"
        case (_, .indeterminate): return "–"
        default: return ""
        }
    }
}

/// The app menu for an app that serves no menu of its own, as the plan
/// has it: built from its desktop entry's name.
struct DefaultAppMenu: View {

    let appName: String

    var body: some View {
        Menu {
            Button("Quit \(appName)") {
                FocusedApp.shared.closeFocusedApp()
            }
        } label: {
            Text(appName)
                .fontWeight(.semibold)
                .lineLimit(1)
        }
    }
}

/// The right side: status items, then the built-in views.
struct StatusArea: View {

    @ObservedObject var statusItems = StatusItems.shared

    var body: some View {
        HStack(spacing: 14) {
            ForEach(statusItems.items) { item in
                StatusItemButton(item: item)
            }
            // Items with menus look like the rest of the bar's.
            .menuStyle(.borderlessButton)
            Image(systemName: "wifi")
            Image(systemName: "speaker.wave.2")
            Clock()
        }
    }
}

struct Clock: View {

    var body: some View {
        TimelineView(.everyMinute) { context in
            Text(Self.formatter.string(from: context.date))
                .monospacedDigit()
        }
    }

    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("EEE MMM d h:mm a")
        return formatter
    }()
}

/// Another app's status item. Until Cacao can look up icon theme names, it
/// shows the item's name. A click opens its menu when the item is a menu,
/// as a Mac app's status item with a menu is, and activates it otherwise;
/// an item that isn't a menu but has one opens it as a context menu.
struct StatusItemButton: View {

    let item: StatusItem

    @ObservedObject var statusItems = StatusItems.shared

    var body: some View {
        if let menu = statusItems.menus[item.id], item.itemIsMenu {
            Menu {
                MenuItems(menu: menu, source: statusItems.source(for: item))
            } label: {
                label
            }
            .help(item.toolTip ?? item.displayName)
        } else if let menu = statusItems.menus[item.id] {
            button
                .contextMenu {
                    MenuItems(menu: menu, source: statusItems.source(for: item))
                }
        } else {
            button
        }
    }

    private var button: some View {
        Button {
            statusItems.activate(item)
        } label: {
            label
        }
        .buttonStyle(.plain)
        .help(item.toolTip ?? item.displayName)
    }

    private var label: some View {
        HStack(spacing: 4) {
            if item.status == .needsAttention {
                Image(systemName: "exclamationmark.circle.fill")
            }
            Text(item.displayName)
                .lineLimit(1)
        }
        .frame(maxWidth: 120)
    }
}
