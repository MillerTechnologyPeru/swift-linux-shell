//
//  Window.swift
//  CacaoWindowServer
//

import CWLRoots
import CacaoShellKit
import DBus

/// An xdg-shell window, as the policy sees it.
@MainActor
final class Window {

    /// The shim's window. Valid until the shim reports it destroyed.
    let toplevel: OpaquePointer

    /// Whether the window is on screen.
    var isMapped = false

    /// Whether the policy has placed the window since it was first mapped.
    var isPlaced = false

    /// Orders windows by when they last had focus.
    var lastFocused: UInt64 = 0

    private(set) var isMinimized = false

    private(set) var isMaximized = false

    private(set) var isFullscreen = false

    /// Where the window was before it was maximized or made full screen,
    /// to go back to.
    var restoreFrame: CWLBox?

    /// Whether the window is on screen and not minimized.
    var isVisible: Bool {
        isMapped && !isMinimized
    }

    init(toplevel: OpaquePointer) {
        self.toplevel = toplevel
    }

    var title: String? {
        cwl_toplevel_title(toplevel).map { String(cString: $0) }
    }

    /// The Wayland app_id, which the dock matches to a desktop entry.
    var appID: String? {
        cwl_toplevel_app_id(toplevel).map { String(cString: $0) }
    }

    /// Where the window's menus are on the session bus, from the appmenu
    /// protocol.
    var appMenu: (service: String, path: String)? {
        guard let service = cwl_toplevel_appmenu_service(toplevel),
              let path = cwl_toplevel_appmenu_path(toplevel)
        else {
            return nil
        }
        return (String(cString: service), String(cString: path))
    }

    /// What the shell is told when the window has focus.
    var focusedWindow: FocusedWindow {
        let menu = appMenu.flatMap { menu in
            DBusBusName(rawValue: menu.service).flatMap { service in
                DBusObjectPath(rawValue: menu.path).map { FocusedWindow.Menu(service: service, path: $0) }
            }
        }
        return FocusedWindow(appID: appID ?? "", title: title ?? "", menu: menu)
    }

        /// The window's position in the layout and its size.
    var geometry: CWLBox {
        cwl_toplevel_geometry(toplevel)
    }

    func move(x: Int32, y: Int32) {
        cwl_toplevel_set_position(toplevel, x, y)
    }

    func resize(width: Int32, height: Int32) {
        cwl_toplevel_set_size(toplevel, width, height)
    }

    func close() {
        cwl_toplevel_close(toplevel)
    }

    /// Moves the window to a frame: its position and its size.
    func setFrame(_ frame: CWLBox) {
        move(x: frame.x, y: frame.y)
        resize(width: frame.width, height: frame.height)
    }

    func setMinimized(_ minimized: Bool) {
        isMinimized = minimized
        cwl_toplevel_set_minimized(toplevel, minimized)
    }

    func setMaximized(_ maximized: Bool) {
        isMaximized = maximized
        cwl_toplevel_set_maximized(toplevel, maximized)
    }

    func setFullscreen(_ fullscreen: Bool) {
        isFullscreen = fullscreen
        cwl_toplevel_set_fullscreen(toplevel, fullscreen)
    }

    /// Moves the window with the pointer until the button is released.
    func beginMove() {
        cwl_toplevel_begin_move(toplevel)
    }

    /// Resizes the window with the pointer from some edges.
    func beginResize(edges: CWLEdges) {
        cwl_toplevel_begin_resize(toplevel, edges)
    }

    private static var focusSerial: UInt64 = 0

    static func nextFocusSerial() -> UInt64 {
        focusSerial += 1
        return focusSerial
    }
}
