//
//  RunningWindows.swift
//  CacaoDock
//

import CacaoSDL
import CacaoShellKit
import Foundation
#if os(Linux)
import CacaoHost
import CToplevelList
#endif

/// An open window, as the compositor's window list reports it.
struct RunningWindow: Identifiable, Equatable, Sendable {

    let id: UInt32

    var appID: String?

    var title: String?

    var isActivated: Bool

    var isMinimized: Bool
}

/// The open windows, from the compositor's wlr-foreign-toplevel-management
/// window list, on a Wayland connection of the dock's own. sway serves it,
/// and CacaoWindowServer will.
///
/// The connection is polled each time the app's loop wakes, so it needs no
/// thread of its own. With no Wayland display, or a compositor without the
/// protocol, the list stays empty.
@MainActor
final class RunningWindows: ObservableObject {

    static let shared = RunningWindows()

    /// In the order they opened.
    @Published private(set) var windows = [RunningWindow]()

    #if os(Linux)
    private var client: OpaquePointer?
    #endif

    private init() {
        #if os(Linux)
        var callbacks = CTLCallbacks()
        callbacks.context = Unmanaged.passUnretained(self).toOpaque()
        callbacks.window_changed = { context, window in
            guard let context else { return }
            let value = RunningWindow(
                id: window.id,
                appID: window.app_id.map { String(cString: $0) },
                title: window.title.map { String(cString: $0) },
                isActivated: window.activated,
                isMinimized: window.minimized
            )
            // Called from `ctl_client_poll`, which runs on the main thread.
            nonisolated(unsafe) let unsafeContext = context
            MainActor.assumeIsolated {
                Unmanaged<RunningWindows>.fromOpaque(unsafeContext).takeUnretainedValue().update(value)
            }
        }
        callbacks.window_closed = { context, id in
            guard let context else { return }
            nonisolated(unsafe) let unsafeContext = context
            MainActor.assumeIsolated {
                Unmanaged<RunningWindows>.fromOpaque(unsafeContext).takeUnretainedValue().remove(id)
            }
        }
        client = ctl_client_connect(callbacks)
        guard client != nil else {
            print("[CacaoDock] The compositor has no window list, so running apps aren't shown")
            return
        }
        HostRuntime.addWakeHook { [weak self] in
            self?.poll()
        }
        #endif
    }

    /// The windows of an app, most recently opened last.
    func windows(of entry: DesktopEntry) -> [RunningWindow] {
        windows.filter { window in
            window.appID.map(entry.matches(appID:)) ?? false
        }
    }

    /// Brings a window forward and focuses it, restoring it if minimized.
    func activate(_ window: RunningWindow) {
        #if os(Linux)
        guard let client else { return }
        ctl_client_activate(client, window.id)
        #endif
    }

    /// Minimizes a window.
    func minimize(_ window: RunningWindow) {
        #if os(Linux)
        guard let client else { return }
        ctl_client_minimize(client, window.id)
        #endif
    }

    #if os(Linux)
    private func poll() {
        guard let client else { return }
        if !ctl_client_poll(client) {
            print("[CacaoDock] Lost the connection to the compositor's window list")
            ctl_client_disconnect(client)
            self.client = nil
            windows = []
        }
    }
    #endif

    private func update(_ window: RunningWindow) {
        if let index = windows.firstIndex(where: { $0.id == window.id }) {
            if windows[index] != window {
                windows[index] = window
            }
        } else {
            windows.append(window)
        }
    }

    private func remove(_ id: UInt32) {
        windows.removeAll { $0.id == id }
    }
}
