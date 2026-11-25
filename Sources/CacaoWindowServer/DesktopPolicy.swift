//
//  DesktopPolicy.swift
//  CacaoWindowServer
//

import CWLRoots

/// Free-floating windows: new windows cascade from the top left of the
/// usable area and take focus, a click focuses and raises, and when the
/// focused window goes away the one focused before it takes over.
///
/// Maximized windows fill the area the menu bar and dock leave; full-screen
/// ones cover the whole screen, above both. Minimized windows are hidden
/// until the dock or another app brings them back.
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
        focusNext(after: window, server: server)
    }

    func shortcut(_ shortcut: Shortcut, server: WindowServer) -> Bool {
        // Super is Command, and Command-Shift-Q logs out. With no dialog to
        // confirm it yet, it ends the session at once; apps get their
        // windows closed with the display.
        if shortcut.matches("q", super: true, shift: true) {
            log("Logging out")
            server.terminate()
            return true
        }
        return false
    }

    func windowClicked(_ window: Window, server: WindowServer) {
        server.focus(window)
    }

    func usableAreaChanged(_ area: CWLBox, server: WindowServer) {
        // Keep each window's top left inside the new area, so the menu bar
        // never covers a title bar, and maximized windows filling it.
        for window in server.mappedWindows where !window.isFullscreen {
            if window.isMaximized {
                window.setFrame(area)
                continue
            }
            let geometry = window.geometry
            let x = min(max(geometry.x, area.x), max(area.x, area.x + area.width - margin))
            let y = min(max(geometry.y, area.y), max(area.y, area.y + area.height - margin))
            if x != geometry.x || y != geometry.y {
                window.move(x: x, y: y)
            }
        }
    }

    // MARK: Requests

    func windowRequestedMove(_ window: Window, server: WindowServer) {
        guard !window.isFullscreen else { return }
        if window.isMaximized {
            // Dragging a maximized window restores its size first.
            restore(window)
        }
        window.beginMove()
    }

    func windowRequestedResize(_ window: Window, edges: CWLEdges, server: WindowServer) {
        guard !window.isMaximized, !window.isFullscreen else { return }
        window.beginResize(edges: edges)
    }

    func windowRequestedMaximize(_ window: Window, _ maximized: Bool, server: WindowServer) {
        guard maximized != window.isMaximized, !window.isFullscreen else { return }
        if maximized {
            window.restoreFrame = window.geometry
            window.setMaximized(true)
            window.setFrame(server.usableArea)
        } else {
            restore(window)
        }
    }

    func windowRequestedFullscreen(_ window: Window, _ fullscreen: Bool, server: WindowServer) {
        guard fullscreen != window.isFullscreen else { return }
        if fullscreen {
            if !window.isMaximized {
                window.restoreFrame = window.geometry
            }
            window.setFullscreen(true)
            window.setFrame(server.outputBox)
            server.focus(window)
        } else {
            window.setFullscreen(false)
            if window.isMaximized {
                window.setFrame(server.usableArea)
            } else if let frame = window.restoreFrame {
                window.setFrame(frame)
                window.restoreFrame = nil
            }
        }
    }

    func windowRequestedMinimize(_ window: Window, _ minimized: Bool, server: WindowServer) {
        guard minimized != window.isMinimized else { return }
        window.setMinimized(minimized)
        if minimized {
            if server.focusedWindow === window {
                focusNext(after: window, server: server)
            }
        } else {
            server.focus(window)
        }
    }

    func windowRequestedActivation(_ window: Window, server: WindowServer) {
        if window.isMinimized {
            window.setMinimized(false)
        }
        server.focus(window)
    }

    // MARK: Helpers

    /// Puts a maximized window back where it was.
    private func restore(_ window: Window) {
        window.setMaximized(false)
        if let frame = window.restoreFrame {
            window.setFrame(frame)
            window.restoreFrame = nil
        }
    }

    /// Focuses the window focused before this one that's still visible, or
    /// nothing.
    private func focusNext(after window: Window, server: WindowServer) {
        if let next = server.visibleWindows.first(where: { $0 !== window }) {
            server.focus(next)
        } else {
            server.clearFocus()
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
