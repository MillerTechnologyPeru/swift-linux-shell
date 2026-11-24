//
//  CacaoDockApp.swift
//  CacaoDock
//
//  The dock: launchers from desktop entries, running apps, and the trash.
//
//  It sits in the top layer of the screen, centered on the bottom edge,
//  and windows stay above it. For now it lists installed apps; it shows
//  running apps once the compositor's window list is read.
//

import CacaoSDL
import CacaoShellKit
import Foundation

@main
struct CacaoDockApp: App {

    /// Read once, since the dock's width depends on how many there are.
    let launchers = Launchers.load()

    init() {
        // The Wayland app_id.
        SDLHost.appIdentifier = "org.pureswift.Cacao.Dock"
    }

    var body: some Scene {
        WindowGroup("Dock") {
            DockView(launchers: launchers)
        }
        // Anchored to the bottom edge alone, so centered along it, and as
        // wide as its icons.
        .defaultSize(width: DockView.width(launcherCount: launchers.count), height: DockView.height)
        .windowLayer(
            .top,
            edges: .bottom,
            exclusiveZone: DockView.height,
            keyboardInteractivity: .none,
            namespace: "cacao-dock"
        )
    }
}

/// The apps the dock shows.
enum Launchers {

    /// How many launchers fit until pinning is configurable.
    static let limit = 12

    static func load() -> [DesktopEntry] {
        Array(
            DesktopEntry.installed()
                .filter { !$0.noDisplay && $0.commandLine != nil }
                .prefix(limit)
        )
    }

    /// Starts an app from its desktop entry.
    static func launch(_ entry: DesktopEntry) {
        guard let commandLine = entry.commandLine else { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = commandLine
        do {
            try process.run()
        } catch {
            print("[CacaoDock] Could not launch \(entry.id): \(error)")
        }
    }
}

struct DockView: View {

    static let height: CGFloat = 84

    static let spacing: CGFloat = 8

    static let padding: CGFloat = 8

    static let dividerWidth: CGFloat = 1

    /// The width that fits the launchers, the divider and the trash.
    static func width(launcherCount: Int) -> CGFloat {
        let icons = CGFloat(launcherCount + 1)
        let gaps = icons // between the icons, and either side of the divider
        return padding * 2 + icons * LauncherIcon.width + dividerWidth + gaps * spacing
    }

    let launchers: [DesktopEntry]

    var body: some View {
        HStack(spacing: Self.spacing) {
            ForEach(launchers, id: \.id) { entry in
                LauncherButton(entry: entry)
            }
            Divider()
                .frame(width: Self.dividerWidth, height: 48)
            LauncherIcon(systemName: "trash", title: "Trash")
        }
        .padding(Self.padding)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct LauncherButton: View {

    let entry: DesktopEntry

    var body: some View {
        Button {
            Launchers.launch(entry)
        } label: {
            // Icon themes come with Cacao's icon theme lookup.
            LauncherIcon(systemName: "square.grid.2x2", title: entry.name)
        }
        .buttonStyle(.plain)
        .help(entry.comment ?? entry.name)
    }
}

struct LauncherIcon: View {

    /// Every icon's width, so the dock's width can be worked out.
    static let width: CGFloat = 56

    let systemName: String

    let title: String

    var body: some View {
        VStack(spacing: 2) {
            Image(systemName: systemName)
                .font(.system(size: 32))
                .frame(width: 48, height: 48)
            Text(title)
                .font(.system(size: 9))
                .lineLimit(1)
        }
        .frame(width: Self.width)
    }
}
