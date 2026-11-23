//
//  DesktopPolicy.swift
//  CacaoWindowServer
//

import CWLRoots

/// Free-floating windows: new windows cascade from the top left of the
/// usable area and take focus, a click focuses and raises, and when the
/// focused window goes away the one focused before it takes over.
@MainActor
final class DesktopPolicy: WindowPolicy {

    /// How far each new window is offset from the last.
    let cascadeStep: Int32 = 32

    /// The margin between the usable area's edge and the first window.
    let margin: Int32 = 24

    private var cascadeIndex: Int32 = 0

    func windowMapped(_ window: Window, server: WindowServer) {
        if !window.isPlaced {
            place(window, in: server.usableArea)
            window.isPlaced = true
        }
        server.focus(window)
    }

    func windowUnmapped(_ window: Window, server: WindowServer) {
        guard server.focusedWindow == nil else { return }
        if let next = server.mappedWindows.first(where: { $0 !== window }) {
            server.focus(next)
        } else {
            server.clearFocus()
        }
    }

    func windowClicked(_ window: Window, server: WindowServer) {
        server.focus(window)
    }

    func usableAreaChanged(_ area: CWLBox, server: WindowServer) {
        // Keep each window's top left inside the new area, so the menu bar
        // never covers a title bar.
        for window in server.mappedWindows {
            let geometry = window.geometry
            let x = min(max(geometry.x, area.x), max(area.x, area.x + area.width - margin))
            let y = min(max(geometry.y, area.y), max(area.y, area.y + area.height - margin))
            if x != geometry.x || y != geometry.y {
                window.move(x: x, y: y)
            }
        }
    }

    private func place(_ window: Window, in area: CWLBox) {
        let size = window.geometry
        var x = area.x + margin + cascadeIndex * cascadeStep
        var y = area.y + margin + cascadeIndex * cascadeStep
        // Start the cascade again once a window would run off the area.
        if x + size.width > area.x + area.width || y + size.height > area.y + area.height {
            cascadeIndex = 0
            x = area.x + margin
            y = area.y + margin
        }
        cascadeIndex += 1
        window.move(x: x, y: y)
    }
}
