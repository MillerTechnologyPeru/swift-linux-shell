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
    }
}

struct MenuBarView: View {

    static let height: CGFloat = 28

    @ObservedObject var appMenus = AppMenus.shared

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: "circle.grid.2x2")
            // The app menu, in bold: the app's own when it serves one, else
            // its name, or the desktop's with no window focused.
            if let appMenu = appMenus.appMenu {
                MenuTitle(menu: appMenu, isAppMenu: true)
            } else {
                Text(appMenus.appName ?? "Desktop")
                    .fontWeight(.semibold)
                    .lineLimit(1)
            }
            ForEach(appMenus.otherMenus) { menu in
                MenuTitle(menu: menu, isAppMenu: false)
            }
            Spacer()
            StatusArea()
        }
        .font(.system(size: 13))
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, minHeight: Self.height, maxHeight: Self.height)
    }
}

/// A menu's title in the bar.
struct MenuTitle: View {

    let menu: DBusMenuItem

    let isAppMenu: Bool

    var body: some View {
        Text(menu.title)
            .fontWeight(isAppMenu ? .semibold : .regular)
            .lineLimit(1)
            .opacity(menu.isEnabled ? 1 : 0.5)
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
/// shows the item's name; a click activates it.
struct StatusItemButton: View {

    let item: StatusItem

    var body: some View {
        Button {
            StatusItems.shared.activate(item)
        } label: {
            HStack(spacing: 4) {
                if item.status == .needsAttention {
                    Image(systemName: "exclamationmark.circle.fill")
                }
                Text(item.displayName)
                    .lineLimit(1)
            }
            .frame(maxWidth: 120)
        }
        .buttonStyle(.plain)
        .help(item.toolTip ?? item.displayName)
    }
}
