//
//  CacaoDesktopApp.swift
//  CacaoDesktop
//
//  The desktop: the wallpaper, in the background layer of the screen, under
//  every window and under the menu bar and dock.
//
//  This is a stand-in. The plan has the file manager own the desktop, with
//  its icons, in a repository of its own; once it exists, the wallpaper
//  moves there and this goes away.
//
//  Usage: CacaoDesktop [--wallpaper image.png]
//
//  With no wallpaper, or one that can't be read, it draws a gradient in the
//  accent color that follows light and dark.
//

import CacaoSDL
import Foundation

@main
struct CacaoDesktopApp: App {

    /// The picture from the command line, read once.
    let wallpaper = Wallpaper.load(arguments: CommandLine.arguments)

    init() {
        // The Wayland app_id.
        SDLHost.appIdentifier = "org.pureswift.Cacao.Desktop"
    }

    var body: some Scene {
        WindowGroup("Desktop") {
            DesktopView(wallpaper: wallpaper)
        }
        // Anchored to every edge, so as big as the screen. An exclusive zone
        // of -1 goes under the space the menu bar and dock keep, too.
        .defaultSize(width: 1280, height: 800)
        .windowLayer(
            .background,
            edges: .all,
            exclusiveZone: -1,
            keyboardInteractivity: .none,
            namespace: "cacao-desktop"
        )
    }
}

enum Wallpaper {

    /// The PNG named by `--wallpaper`, if there is one and it can be read.
    static func load(arguments: [String]) -> Image? {
        guard let index = arguments.firstIndex(of: "--wallpaper"),
              arguments.indices.contains(index + 1)
        else { return nil }
        let path = arguments[index + 1]
        guard let data = FileManager.default.contents(atPath: path) else {
            print("[CacaoDesktop] Can't read the wallpaper \(path); drawing the default")
            return nil
        }
        return Image(pngData: data)
    }
}

struct DesktopView: View {

    let wallpaper: Image?

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            if let wallpaper {
                wallpaper
                    .resizable()
                    .scaledToFill()
            } else {
                Rectangle()
                    .fill(defaultGradient)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// The accent color fading into a neutral ground from the top left.
    private var defaultGradient: LinearGradient {
        let isDark = colorScheme == .dark
        let ground = isDark ? Color(white: 0.11) : Color(white: 0.86)
        let tint = Color.accentColor.mix(with: ground, by: isDark ? 0.55 : 0.45)
        return LinearGradient(
            gradient: Gradient(colors: [tint, ground.mix(with: tint, by: 0.15), ground]),
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}
