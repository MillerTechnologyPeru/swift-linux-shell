//
//  WindowServer.swift
//  CacaoWindowServer
//

import CWLRoots
import CacaoShellKit
import Foundation

/// The compositor: the wlroots shim with window policy in Swift.
///
/// The shim reports windows and input through C callbacks, which arrive on
/// the main thread while `run()` is in the event loop. Each is handed to the
/// policy for the screen's form factor.
@MainActor
final class WindowServer {

    private var server: OpaquePointer?

    private var windows = [OpaquePointer: Window]()

    /// Decides placement, focus and stacking.
    let policy: any WindowPolicy

    /// The area left for windows by the menu bar and the dock.
    private(set) var usableArea = CWLBox()

    /// The window with keyboard focus.
    private(set) var focusedWindow: Window?

    init(policy: any WindowPolicy) {
        self.policy = policy
    }

    /// Creates the display and backend and opens the Wayland socket.
    ///
    /// - Returns: The socket name, which clients find in `WAYLAND_DISPLAY`.
    func start() throws(WindowServerError) -> String {
        var callbacks = CWLServerCallbacks()
        callbacks.context = Unmanaged.passUnretained(self).toOpaque()
        callbacks.toplevel_mapped = { context, toplevel in
            WindowServer.dispatch(context, toplevel) { $0.toplevelMapped($1) }
        }
        callbacks.toplevel_unmapped = { context, toplevel in
            WindowServer.dispatch(context, toplevel) { $0.toplevelUnmapped($1) }
        }
        callbacks.toplevel_destroyed = { context, toplevel in
            WindowServer.dispatch(context, toplevel) { $0.toplevelDestroyed($1) }
        }
        callbacks.toplevel_changed = { context, toplevel in
            WindowServer.dispatch(context, toplevel) { $0.toplevelChanged($1) }
        }
        callbacks.toplevel_appmenu_changed = { context, toplevel in
            WindowServer.dispatch(context, toplevel) { $0.toplevelAppMenuChanged($1) }
        }
        callbacks.toplevel_clicked = { context, toplevel in
            WindowServer.dispatch(context, toplevel) { $0.toplevelClicked($1) }
        }
        callbacks.usable_area_changed = { context, area in
            guard let context else { return }
            nonisolated(unsafe) let unsafeContext = context
            MainActor.assumeIsolated {
                let context = unsafeContext
                Unmanaged<WindowServer>.fromOpaque(context).takeUnretainedValue().usableAreaChanged(area)
            }
        }
        callbacks.expose_requested = { context, mode, appID in
            guard let context else { return }
            let appID = appID.map { String(cString: $0) }
            nonisolated(unsafe) let unsafeContext = context
            MainActor.assumeIsolated {
                let context = unsafeContext
                let server = Unmanaged<WindowServer>.fromOpaque(context).takeUnretainedValue()
                server.exposeRequested(DockProtocol.ExposeMode(rawValue: mode.rawValue) ?? .allWindows, appID: appID)
            }
        }

        guard let server = cwl_server_create(callbacks) else {
            throw .backend
        }
        self.server = server
        guard let socket = cwl_server_start(server) else {
            throw .socket
        }
        return String(cString: socket)
    }

    /// Runs the event loop until `terminate()`.
    func run() {
        guard let server else { return }
        cwl_server_run(server)
    }

    func terminate() {
        guard let server else { return }
        cwl_server_terminate(server)
    }

    /// Disconnects every client and frees the server.
    func shutDown() {
        guard let server else { return }
        cwl_server_destroy(server)
        self.server = nil
        windows.removeAll()
        focusedWindow = nil
    }

    // MARK: Actions for the policy

    /// Raises a window, activates it and gives it keyboard focus.
    func focus(_ window: Window) {
        cwl_toplevel_focus(window.toplevel)
        guard focusedWindow !== window else { return }
        focusedWindow = window
        focusChanged()
    }

    /// Focuses nothing, as when the last window goes away.
    func clearFocus() {
        guard focusedWindow != nil else { return }
        focusedWindow = nil
        focusChanged()
    }

    /// Every mapped window, most recently focused first.
    var mappedWindows: [Window] {
        windows.values.filter(\.isMapped).sorted { $0.lastFocused > $1.lastFocused }
    }

    // MARK: Callbacks

    nonisolated private static func dispatch(
        _ context: UnsafeMutableRawPointer?,
        _ toplevel: OpaquePointer?,
        _ body: @MainActor (WindowServer, OpaquePointer) -> Void
    ) {
        guard let context, let toplevel else { return }
        // The shim calls back on the main thread, from inside
        // wl_display_run, so the pointers never cross threads.
        nonisolated(unsafe) let unsafeContext = context
        nonisolated(unsafe) let unsafeToplevel = toplevel
        MainActor.assumeIsolated {
            body(Unmanaged<WindowServer>.fromOpaque(unsafeContext).takeUnretainedValue(), unsafeToplevel)
        }
    }

    private func window(for toplevel: OpaquePointer) -> Window {
        if let window = windows[toplevel] {
            return window
        }
        let window = Window(toplevel: toplevel)
        windows[toplevel] = window
        return window
    }

    private func toplevelMapped(_ toplevel: OpaquePointer) {
        let window = window(for: toplevel)
        window.isMapped = true
        policy.windowMapped(window, server: self)
    }

    private func toplevelUnmapped(_ toplevel: OpaquePointer) {
        guard let window = windows[toplevel] else { return }
        window.isMapped = false
        if focusedWindow === window {
            focusedWindow = nil
        }
        policy.windowUnmapped(window, server: self)
    }

    private func toplevelDestroyed(_ toplevel: OpaquePointer) {
        guard let window = windows.removeValue(forKey: toplevel) else { return }
        window.isMapped = false
        if focusedWindow === window {
            focusedWindow = nil
            policy.windowUnmapped(window, server: self)
        }
    }

    private func toplevelChanged(_ toplevel: OpaquePointer) {
        guard let window = windows[toplevel], window === focusedWindow else { return }
        focusChanged()
    }

    private func toplevelAppMenuChanged(_ toplevel: OpaquePointer) {
        guard let window = windows[toplevel], window === focusedWindow else { return }
        focusChanged()
    }

    private func toplevelClicked(_ toplevel: OpaquePointer) {
        guard let window = windows[toplevel], window.isMapped else { return }
        policy.windowClicked(window, server: self)
    }

    private func usableAreaChanged(_ area: CWLBox) {
        usableArea = area
        log("Usable area: \(area.width)×\(area.height) at \(area.x),\(area.y)")
        policy.usableAreaChanged(area, server: self)
    }

    private func exposeRequested(_ mode: DockProtocol.ExposeMode, appID: String?) {
        log("Exposé requested: \(mode), app \(appID ?? "none"). Not implemented yet.")
    }

    /// The menu bar will follow focus through this. Until the menu bar's
    /// link to the compositor exists, it is logged.
    private func focusChanged() {
        guard let window = focusedWindow else {
            log("Focus: none")
            return
        }
        window.lastFocused = Window.nextFocusSerial()
        let menu = window.appMenu.map { "\($0.service) \($0.path)" } ?? "no exported menu"
        log("Focus: \(window.appID ?? "unknown app") \"\(window.title ?? "")\", \(menu)")
    }
}

enum WindowServerError: Error, CustomStringConvertible {

    /// No backend, renderer or allocator could be created.
    case backend

    /// The Wayland socket could not be opened, or the backend did not start.
    case socket

    var description: String {
        switch self {
        case .backend:
            return "Could not create the wlroots backend, renderer and allocator"
        case .socket:
            return "Could not open a Wayland socket or start the backend"
        }
    }
}

func log(_ message: String) {
    // Standard error, which is unbuffered, so lines survive the process being killed.
    FileHandle.standardError.write(Data("[CacaoWindowServer] \(message)\n".utf8))
}
