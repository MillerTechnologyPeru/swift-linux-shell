//
//  Window.swift
//  CacaoWindowServer
//

import CWLRoots

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

    private static var focusSerial: UInt64 = 0

    static func nextFocusSerial() -> UInt64 {
        focusSerial += 1
        return focusSerial
    }
}
