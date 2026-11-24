//
//  CacaoDockApp.swift
//  CacaoDock
//
//  The dock: launchers from desktop entries, running apps, and the trash.
//
//  It sits in the top layer of the screen, centered on the bottom edge,
//  and windows stay above it. Running apps come from the compositor's
//  window list: a dot marks a launcher whose app is open, clicking it
//  focuses the app's window, and apps without a launcher get icons of their
//  own after the launchers.
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
        // Anchored to the bottom edge alone, so centered along it. A layer
        // surface keeps the size it opened with, so it has room for a few
        // running apps without launchers, and the trash.
        .defaultSize(
            width: DockView.width(iconCount: launchers.count + DockView.otherAppSlots + 1),
            height: DockView.height
        )
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

    /// Every installed app, for naming running apps without a launcher.
    static let installed = DesktopEntry.installed()

    static func load() -> [DesktopEntry] {
        Array(
            installed
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

    /// Focuses an app's window, or minimizes it if it already has focus,
    /// as a dock does.
    @MainActor
    static func toggle(_ windows: [RunningWindow]) {
        let running = RunningWindows.shared
        if let focused = windows.first(where: \.isActivated), !focused.isMinimized {
            running.minimize(focused)
        } else if let window = windows.last {
            running.activate(window)
        }
    }
}

/// A running app with no launcher in the dock.
struct OtherApp: Identifiable {

    /// Its app_id.
    let id: String

    let name: String

    let windows: [RunningWindow]
}

struct DockView: View {

    static let height: CGFloat = 84

    static let spacing: CGFloat = 8

    static let padding: CGFloat = 8

    static let dividerWidth: CGFloat = 1

    /// How many running apps without launchers get an icon.
    static let otherAppSlots = 4

    /// The width that fits some icons and the divider.
    static func width(iconCount: Int) -> CGFloat {
        let icons = CGFloat(iconCount)
        // Between the icons, and one more for the divider.
        let gaps = icons
        return padding * 2 + icons * LauncherIcon.width + dividerWidth + gaps * spacing
    }

    let launchers: [DesktopEntry]

    @ObservedObject var running = RunningWindows.shared

    var body: some View {
        HStack(spacing: Self.spacing) {
            ForEach(launchers, id: \.id) { entry in
                LauncherButton(entry: entry, windows: running.windows(of: entry))
            }
            ForEach(otherApps) { app in
                Button {
                    Launchers.toggle(app.windows)
                } label: {
                    LauncherIcon(systemName: "macwindow", title: app.name, isRunning: true)
                }
                .buttonStyle(.plain)
                .help(app.windows.last?.title ?? app.name)
            }
            Divider()
                .frame(width: Self.dividerWidth, height: 48)
            LauncherIcon(systemName: "trash", title: "Trash")
        }
        .padding(Self.padding)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Running apps that match no launcher, one per app_id, in the order
    /// they opened.
    var otherApps: [OtherApp] {
        var apps = [OtherApp]()
        for window in running.windows {
            guard let appID = window.appID, !appID.isEmpty,
                  !launchers.contains(where: { $0.matches(appID: appID) })
            else { continue }
            if let index = apps.firstIndex(where: { $0.id == appID }) {
                apps[index] = OtherApp(id: appID, name: apps[index].name, windows: apps[index].windows + [window])
            } else {
                // With no desktop entry, the app_id's last part: CacaoDemo for
                // org.pureswift.CacaoDemo.
                let name = Launchers.installed.first { $0.matches(appID: appID) }?.name
                    ?? appID.split(separator: ".").last.map(String.init) ?? appID
                apps.append(OtherApp(id: appID, name: name, windows: [window]))
            }
        }
        return Array(apps.prefix(Self.otherAppSlots))
    }
}

struct LauncherButton: View {

    let entry: DesktopEntry

    /// The app's open windows.
    let windows: [RunningWindow]

    var body: some View {
        Button {
            if windows.isEmpty {
                Launchers.launch(entry)
            } else {
                Launchers.toggle(windows)
            }
        } label: {
            // Icon themes come with Cacao's icon theme lookup.
            LauncherIcon(systemName: "square.grid.2x2", title: entry.name, isRunning: !windows.isEmpty)
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

    var isRunning = false

    var body: some View {
        VStack(spacing: 2) {
            Image(systemName: systemName)
                .font(.system(size: 32))
                .frame(width: 48, height: 48)
            Text(title)
                .font(.system(size: 9))
                .lineLimit(1)
            // Marks an open app.
            Circle()
                .frame(width: 4, height: 4)
                .opacity(isRunning ? 1 : 0)
        }
        .frame(width: Self.width)
    }
}
