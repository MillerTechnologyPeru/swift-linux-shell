//
//  WindowServerActions.swift
//  CacaoShellKit
//

import DBus

/// The session's actions on the window server's interface,
/// `org.pureswift.Cacao.WindowServer1`, beside the focused window
/// (`FocusedWindow`).
///
/// The window server takes the Mac's shortcuts for them. Those that ask
/// first, Log Out… and Force Quit…, it hands to the shell with the
/// `ActionRequested` signal, and the menu bar shows the dialog. The menu
/// bar then calls `LogOut` or `ForceQuit`, as its own system menu does.
public enum WindowServerActions {

    /// Ends the session: the window server quits, and apps lose their
    /// windows with the display. No arguments.
    public static let logOut = DBusMember(rawValue: "LogOut")!

    /// Ends an app at once: `s app_id`.
    public static let forceQuit = DBusMember(rawValue: "ForceQuit")!

    /// The window server asks the shell to show an action's dialog: `s`,
    /// an `Action`'s raw value.
    public static let actionRequested = DBusMember(rawValue: "ActionRequested")!

    public static let actionRequestedSignal = DBusMessage.Signal(
        path: ShellDBus.windowServerPath,
        interface: ShellDBus.windowServerInterface,
        name: actionRequested
    )

    /// What the shell is asked to show.
    public enum Action: String, Sendable, CaseIterable {

        /// The Log Out… dialog, for Shift-Command-Q.
        case logOut = "log-out"

        /// The Force Quit window, for Option-Command-Escape.
        case forceQuit = "force-quit"
    }
}
