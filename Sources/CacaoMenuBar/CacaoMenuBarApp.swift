//
//  CacaoMenuBarApp.swift
//  CacaoMenuBar
//
//  The menu bar: the focused app's menus at the left, status items and the
//  clock at the right.
//
//  It sits in the top layer of the screen along the top edge, and windows
//  stay below it. It reads menus once the compositor reports the focused
//  window's dbusmenu address.
//

import CacaoSDL
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

    /// Shown until the focused app's menus can be read: the default app
    /// menu every app gets.
    let menuTitles = ["File", "Edit", "View", "Window", "Help"]

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: "circle.grid.2x2")
            Text("Desktop")
                .fontWeight(.semibold)
            ForEach(menuTitles, id: \.self) { title in
                Text(title)
            }
            Spacer()
            StatusArea()
        }
        .font(.system(size: 13))
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, minHeight: Self.height, maxHeight: Self.height)
    }
}

/// The right side: status items, then the built-in views.
struct StatusArea: View {

    var body: some View {
        HStack(spacing: 14) {
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
