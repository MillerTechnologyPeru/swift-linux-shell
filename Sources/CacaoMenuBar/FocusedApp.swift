//
//  FocusedApp.swift
//  CacaoMenuBar
//

import CacaoSDL
import Foundation
#if os(Linux)
import CacaoHost
import CToplevelList
#endif

/// The app whose window has focus, by its Wayland `app_id`.
///
/// For now it comes from the compositor's wlr-foreign-toplevel-management
/// window list, which sway serves: the window marked activated. Once
/// CacaoWindowServer replaces sway, the compositor tells the menu bar the
/// focused window and its menu address through the appmenu protocol
/// instead, and this goes away.
@MainActor
final class FocusedApp {

    static let shared = FocusedApp()

    /// The focused window's `app_id`, or nil when no window has focus.
    private(set) var appID: String?

    /// Called with the new `app_id` each time focus moves to another app.
    var onChange: ((String?) -> Void)?

    #if os(Linux)
    private var client: OpaquePointer?

    /// The `app_id` and focus of each open window, by its number.
    private var windows = [UInt32: (appID: String?, isActivated: Bool)]()
    #endif

    private init() {
        #if os(Linux)
        var callbacks = CTLCallbacks()
        callbacks.context = Unmanaged.passUnretained(self).toOpaque()
        callbacks.window_changed = { context, window in
            guard let context else { return }
            let id = window.id
            let appID = window.app_id.map { String(cString: $0) }
            let isActivated = window.activated
            // Called from `ctl_client_poll`, on the main thread.
            nonisolated(unsafe) let unsafeContext = context
            MainActor.assumeIsolated {
                let focused = Unmanaged<FocusedApp>.fromOpaque(unsafeContext).takeUnretainedValue()
                focused.windows[id] = (appID, isActivated)
                focused.update()
            }
        }
        callbacks.window_closed = { context, id in
            guard let context else { return }
            nonisolated(unsafe) let unsafeContext = context
            MainActor.assumeIsolated {
                let focused = Unmanaged<FocusedApp>.fromOpaque(unsafeContext).takeUnretainedValue()
                focused.windows[id] = nil
                focused.update()
            }
        }
        client = ctl_client_connect(callbacks)
        guard client != nil else {
            print("[CacaoMenuBar] The compositor has no window list, so the menu bar can't follow focus")
            return
        }
        HostRuntime.addWakeHook { [weak self] in
            self?.poll()
        }
        #endif
    }

    /// Asks every window of the focused app to close: the default app
    /// menu's Quit, for apps that serve no menu of their own.
    func closeFocusedApp() {
        #if os(Linux)
        guard let client, let appID else { return }
        for (id, window) in windows where window.appID == appID {
            ctl_client_close(client, id)
        }
        #endif
    }

    #if os(Linux)
    private func poll() {
        guard let client else { return }
        if !ctl_client_poll(client) {
            print("[CacaoMenuBar] Lost the connection to the compositor's window list")
            ctl_client_disconnect(client)
            self.client = nil
            windows = [:]
            update()
        }
    }

    private func update() {
        let focused: String?
        if let activated = windows.values.first(where: \.isActivated) {
            focused = activated.appID
        } else if let appID, windows.values.contains(where: { $0.appID == appID }) {
            // Focus went to no window: to the menu bar itself, when one of
            // its menus is clicked, or to the desktop. The app keeps the
            // bar while it has a window open.
            focused = appID
        } else {
            focused = nil
        }
        if focused != appID {
            appID = focused
            onChange?(focused)
        }
    }
    #endif
}
