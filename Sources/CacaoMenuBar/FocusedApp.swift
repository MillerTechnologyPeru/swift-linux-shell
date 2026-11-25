//
//  FocusedApp.swift
//  CacaoMenuBar
//

import CacaoSDL
import CacaoShellKit
import DBus
import Foundation
#if os(Linux)
import CacaoHost
import CToplevelList
#endif

/// The app whose window has focus, by its Wayland `app_id`, and where that
/// window's menus are when the compositor knows.
///
/// Under CacaoWindowServer, focus and the menu address come from the
/// compositor's `org.pureswift.Cacao.WindowServer1` interface, which takes
/// the address from the appmenu protocol. Under other compositors, such as
/// sway, focus comes from the wlr-foreign-toplevel-management window list,
/// the window marked activated, and the menu is found by `app_id`.
@MainActor
final class FocusedApp {

    static let shared = FocusedApp()

    /// The focused window's `app_id`, or nil when no window has focus.
    private(set) var appID: String?

    /// Where the focused window's menus are, when the compositor says.
    private(set) var menu: FocusedWindow.Menu?

    /// Called each time focus moves to another app, or to a window of the
    /// same app with other menus.
    var onChange: (() -> Void)?

    /// Whether focus comes from the window server rather than the window
    /// list.
    private var usesWindowServer = false

    /// The focused window, as the window server last said.
    private var reportedWindow: FocusedWindow?

    /// The `app_id` and focus of each open window, by its number, from the
    /// window list. The window list also closes an app's windows.
    private var windows = [UInt32: (appID: String?, isActivated: Bool)]()

    #if os(Linux)
    private var client: OpaquePointer?
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

    /// Follows focus through the window server, when the compositor serves
    /// its interface; otherwise focus keeps coming from the window list.
    func useWindowServer(on connection: DBusConnection) async {
        do {
            guard try await connection.nameHasOwner(ShellDBus.windowServerName) else {
                return
            }
            // Signals come from the owner's unique name, which the match
            // has to name. Listen before asking, so no change is missed in
            // between.
            let owner = try await connection.getNameOwner(ShellDBus.windowServerName)
            let changes = try await connection.signals(
                interface: ShellDBus.windowServerInterface,
                member: FocusedWindow.focusChanged,
                sender: owner
            )
            let reply = try await connection.callMethod(
                destination: ShellDBus.windowServerName,
                path: ShellDBus.windowServerPath,
                interface: ShellDBus.windowServerInterface,
                method: FocusedWindow.getFocusedWindow
            )
            guard let window = FocusedWindow.parse(reply) else {
                print("[CacaoMenuBar] The window server's reply wasn't understood")
                return
            }
            print("[CacaoMenuBar] Following focus through the window server")
            usesWindowServer = true
            report(window)
            Task { [weak self] in
                for await message in changes {
                    guard let window = FocusedWindow.parse(message.arguments) else { continue }
                    self?.report(window)
                }
            }
            // The shortcuts the window server takes whose dialogs the menu
            // bar shows, such as Shift-Command-Q's Log Out….
            let actions = try await connection.signals(
                interface: ShellDBus.windowServerInterface,
                member: WindowServerActions.actionRequested,
                sender: owner
            )
            Task {
                for await message in actions {
                    guard case let .string(name)? = message.arguments.first,
                          let action = WindowServerActions.Action(rawValue: name)
                    else { continue }
                    SystemActions.shared.handle(action)
                }
            }
        } catch {
            print("[CacaoMenuBar] Couldn't follow the window server's focus: \(error)")
        }
    }

    /// The `app_id`s of the apps with windows open.
    var runningAppIDs: [String] {
        Array(Set(windows.values.compactMap(\.appID)))
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

    private func report(_ window: FocusedWindow?) {
        reportedWindow = window
        update()
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
    #endif

    private func update() {
        var focused: (appID: String, menu: FocusedWindow.Menu?)?
        if usesWindowServer {
            focused = reportedWindow.map { ($0.appID, $0.menu) }
        } else if let activated = windows.values.first(where: \.isActivated) {
            focused = activated.appID.map { ($0, nil) }
        }
        if focused == nil, let appID, windows.values.contains(where: { $0.appID == appID }) {
            // Focus went to no window: to the desktop, or to the menu bar
            // itself under compositors that move focus to it. The app keeps
            // the bar while it has a window open.
            focused = (appID, menu)
        }
        if focused?.appID != appID || focused?.menu != menu {
            appID = focused?.appID
            menu = focused?.menu
            onChange?()
        }
    }
}
