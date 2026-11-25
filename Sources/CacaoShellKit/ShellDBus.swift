//
//  ShellDBus.swift
//  CacaoShellKit
//

import DBus

/// The D-Bus names the shell processes and apps meet at. All but the
/// settings service's are existing interfaces, so apps written for other
/// desktops work unchanged.
public enum ShellDBus {

    // MARK: Menus

    /// An app's menus, read by the menu bar.
    public static let dbusMenuInterface = DBusInterface(rawValue: "com.canonical.dbusmenu")!

    /// The registry of X11 windows' menus. The menu bar owns it, because
    /// apps such as Qt's and Perry's take an owner as the sign that a global
    /// menu bar shows their menus, and hide their own.
    public static let appMenuRegistrarName = DBusBusName(rawValue: "com.canonical.AppMenu.Registrar")!
    public static let appMenuRegistrarInterface = DBusInterface(rawValue: "com.canonical.AppMenu.Registrar")!
    public static let appMenuRegistrarPath = DBusObjectPath(rawValue: "/com/canonical/AppMenu/Registrar")!

    // MARK: Status items

    /// The watcher the menu bar hosts, which status items register with.
    public static let statusNotifierWatcherName = DBusBusName(rawValue: "org.kde.StatusNotifierWatcher")!
    public static let statusNotifierWatcherInterface = DBusInterface(rawValue: "org.kde.StatusNotifierWatcher")!
    public static let statusNotifierWatcherPath = DBusObjectPath(rawValue: "/StatusNotifierWatcher")!

    /// A status item, shown at the right of the menu bar.
    public static let statusNotifierItemInterface = DBusInterface(rawValue: "org.kde.StatusNotifierItem")!

    // MARK: Dock

    /// Badges, progress, urgency and dock menus for launchers. Apps emit its
    /// `Update` signal and the dock listens.
    public static let launcherEntryInterface = DBusInterface(rawValue: "com.canonical.Unity.LauncherEntry")!

    // MARK: Notifications

    public static let notificationsName = DBusBusName(rawValue: "org.freedesktop.Notifications")!
    public static let notificationsInterface = DBusInterface(rawValue: "org.freedesktop.Notifications")!
    public static let notificationsPath = DBusObjectPath(rawValue: "/org/freedesktop/Notifications")!

    // MARK: Portal

    /// The name the settings service owns as the desktop's portal backend.
    /// xdg-desktop-portal finds it through `Data/cacao.portal`.
    public static let portalBackendName = DBusBusName(rawValue: "org.freedesktop.impl.portal.desktop.cacao")!

    /// The path every portal backend serves.
    public static let portalPath = DBusObjectPath(rawValue: "/org/freedesktop/portal/desktop")!

    /// The interface the backend implements for settings.
    public static let portalSettingsBackendInterface = DBusInterface(rawValue: "org.freedesktop.impl.portal.Settings")!

    /// The interface apps call on xdg-desktop-portal, which forwards to the
    /// backend.
    public static let portalSettingsInterface = DBusInterface(rawValue: "org.freedesktop.portal.Settings")!
    public static let portalName = DBusBusName(rawValue: "org.freedesktop.portal.Desktop")!

    // MARK: Settings service

    /// The settings service's own interface, for the shell to change values.
    /// Apps read settings through the portal, never through this.
    public static let settingsName = DBusBusName(rawValue: "org.pureswift.Cacao.Settings")!
    public static let settingsInterface = DBusInterface(rawValue: "org.pureswift.Cacao.Settings1")!
    public static let settingsPath = DBusObjectPath(rawValue: "/org/pureswift/Cacao/Settings")!

    // MARK: Window server

    /// The compositor's own interface, which tells the shell which window
    /// has focus and where its menus are. See `FocusedWindow`.
    public static let windowServerName = DBusBusName(rawValue: "org.pureswift.Cacao.WindowServer")!
    public static let windowServerInterface = DBusInterface(rawValue: "org.pureswift.Cacao.WindowServer1")!
    public static let windowServerPath = DBusObjectPath(rawValue: "/org/pureswift/Cacao/WindowServer")!
}
