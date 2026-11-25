//
//  DesktopPolicy.swift
//  CacaoWindowServer
//

import CWLRoots
import CacaoShellKit
import Foundation

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

    /// The last press on a title bar, to tell a double click.
    private var lastTitleBarPress: (window: ObjectIdentifier, time: Date)?

    /// How soon a second press on a title bar is a double click.
    let doubleClickInterval: TimeInterval = 0.4

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
        // The Mac's, with Super as Command. Those with a dialog the shell
        // shows; logging out without one the window server does itself.
        // Control-Command-Q, Lock Screen, is left to apps until there's a
        // lock screen.
        if shortcut.matches("q", super: true, shift: true, alt: true) {
            // Option-Shift-Command-Q: Log Out, without asking.
            server.logOut()
            return true
        }
        if shortcut.matches("q", super: true, shift: true) {
            // Shift-Command-Q: Log Out…, which asks first.
            server.requestShellAction(.logOut)
            return true
        }
        if shortcut.matches(keysym: Shortcut.escape, super: true, alt: true) {
            // Option-Command-Escape: Force Quit….
            server.requestShellAction(.forceQuit)
            return true
        }
        return exposeShortcut(shortcut, server: server) || spaceShortcut(shortcut, server: server)
    }

    // MARK: Exposé

    /// What Exposé shows while it's showing.
    private var exposeMode: DockProtocol.ExposeMode?

    /// The Mac's: Control-Up for every window, as Mission Control; Control-
    /// Down for the focused app's; Command-F3 to show the desktop. Each
    /// ends Exposé when it's showing.
    private func exposeShortcut(_ shortcut: Shortcut, server: WindowServer) -> Bool {
        if shortcut.matches(keysym: Shortcut.up, control: true) {
            expose(.allWindows, appID: nil, server: server)
            return true
        }
        if shortcut.matches(keysym: Shortcut.down, control: true) {
            expose(.appWindows, appID: server.focusedWindow?.appID, server: server)
            return true
        }
        if shortcut.matches(keysym: Shortcut.f3, super: true) {
            expose(.desktop, appID: nil, server: server)
            return true
        }
        return false
    }

    func expose(_ mode: DockProtocol.ExposeMode, appID: String?, server: WindowServer) {
        if exposeMode != nil {
            endExpose(focusing: nil, server: server)
            return
        }
        let windows = server.visibleWindows
        let shown: [Window]
        switch mode {
        case .allWindows:
            shown = windows
        case .appWindows:
            guard let appID else { return }
            shown = windows.filter { $0.appID == appID }
        case .desktop:
            shown = []
        }
        guard mode == .desktop || !shown.isEmpty else { return }
        server.beginExpose()
        exposeMode = mode
        for window in windows where !shown.contains(where: { $0 === window }) {
            window.hideForExpose()
        }
        let boxes = Self.exposeLayout(count: shown.count, in: server.usableArea)
        for (window, box) in zip(shown, boxes) {
            window.showPreview(in: box)
        }
    }

    func exposeChose(_ window: Window?, server: WindowServer) {
        endExpose(focusing: window, server: server)
    }

    func exposeKey(_ keysym: UInt32, server: WindowServer) {
        if keysym == Shortcut.escape {
            endExpose(focusing: nil, server: server)
        }
    }

    private func endExpose(focusing window: Window?, server: WindowServer) {
        exposeMode = nil
        server.endExpose()
        if let window {
            server.focus(window)
        }
    }

    /// Boxes for windows in a grid filling an area, in reading order, with
    /// room between them.
    static func exposeLayout(count: Int, in area: CWLBox) -> [CWLBox] {
        guard count > 0, area.width > 0, area.height > 0 else { return [] }
        let margin: Int32 = 48
        let spacing: Int32 = 24
        let width = area.width - margin * 2
        let height = area.height - margin * 2
        // As many columns as keep the cells about as wide as the area's
        // shape suggests.
        let aspect = Double(width) / Double(max(height, 1))
        let columns = max(1, min(count, Int((Double(count) * aspect).squareRoot().rounded(.up))))
        let rows = Int((Double(count) / Double(columns)).rounded(.up))
        let cellWidth = (width - spacing * Int32(columns - 1)) / Int32(columns)
        let cellHeight = (height - spacing * Int32(rows - 1)) / Int32(rows)
        return (0..<count).map { index in
            let row = index / columns
            let column = index % columns
            // The last row's cells are centered.
            let inRow = row == rows - 1 ? count - row * columns : columns
            let rowWidth = Int32(inRow) * cellWidth + Int32(inRow - 1) * spacing
            let left = area.x + margin + (width - rowWidth) / 2
            return CWLBox(
                x: left + Int32(column) * (cellWidth + spacing),
                y: area.y + margin + Int32(row) * (cellHeight + spacing),
                width: cellWidth,
                height: cellHeight
            )
        }
    }

    // MARK: Spaces

    /// The Mac's shortcuts for spaces: Control-Left and Right to the space
    /// beside, Control-1 to 4 to a space. With Shift, Control-Left and
    /// Right take the focused window along.
    private func spaceShortcut(_ shortcut: Shortcut, server: WindowServer) -> Bool {
        let current = server.currentSpace
        for (keysym, step) in [(Shortcut.left, -1), (Shortcut.right, 1)] {
            if shortcut.matches(keysym: keysym, control: true) {
                show(space: current + step, server: server)
                return true
            }
            if shortcut.matches(keysym: keysym, shift: true, control: true) {
                if let window = server.focusedWindow {
                    move(window, toSpace: current + step, server: server)
                }
                return true
            }
        }
        for space in 0..<WindowServer.spaceCount {
            let digit = UInt32(Character("1").asciiValue! + UInt8(space))
            if shortcut.matches(keysym: digit, control: true) {
                show(space: space, server: server)
                return true
            }
        }
        return false
    }

    /// Shows a space and focuses the window used last on it.
    func show(space: Int, server: WindowServer) {
        guard (0..<WindowServer.spaceCount).contains(space), space != server.currentSpace else { return }
        if exposeMode != nil {
            endExpose(focusing: nil, server: server)
        }
        server.showSpace(space)
        if let next = server.visibleWindows.first {
            server.focus(next)
        } else {
            server.clearFocus()
        }
    }

    /// Moves a window to another space, and goes there with it.
    func move(_ window: Window, toSpace space: Int, server: WindowServer) {
        guard (0..<WindowServer.spaceCount).contains(space), space != window.space else { return }
        window.setSpace(space)
        server.showSpace(space)
        server.focus(window)
    }

    // MARK: Title bars

    func windowTitleBarPressed(_ window: Window, at point: CGPoint, server: WindowServer) {
        server.focus(window)
        // The buttons act when the pointer comes up on them.
        if let button = TitleBar.button(at: point, width: Int(window.geometry.width)) {
            window.pressedTitleBarButton = button
            lastTitleBarPress = nil
            return
        }
        let now = Date()
        if let last = lastTitleBarPress, last.window == ObjectIdentifier(window),
           now.timeIntervalSince(last.time) < doubleClickInterval {
            // A double click zooms, as the maximize button does.
            lastTitleBarPress = nil
            windowRequestedMaximize(window, !window.isMaximized, server: server)
            return
        }
        lastTitleBarPress = (ObjectIdentifier(window), now)
        // Dragging the title bar moves the window; a maximized one stays.
        if !window.isMaximized, !window.isFullscreen {
            window.beginMove()
        }
    }

    func windowTitleBarReleased(_ window: Window, at point: CGPoint, server: WindowServer) {
        guard let pressed = window.pressedTitleBarButton else { return }
        window.pressedTitleBarButton = nil
        guard TitleBar.button(at: point, width: Int(window.geometry.width)) == pressed else { return }
        switch pressed {
        case .close:
            window.close()
        case .minimize:
            windowRequestedMinimize(window, true, server: server)
        case .maximize:
            windowRequestedMaximize(window, !window.isMaximized, server: server)
        @unknown default:
            // A button Cacao's layouts gain later; the title bar shows only
            // these.
            break
        }
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
        // A window on another space: that space comes to it.
        if window.space != server.currentSpace {
            server.showSpace(window.space)
        }
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
