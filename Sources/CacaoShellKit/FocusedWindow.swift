//
//  FocusedWindow.swift
//  CacaoShellKit
//

import DBus

/// The window that has focus, as the window server tells the menu bar: its
/// app, its title, and where its menus are on the session bus.
///
/// The window server serves it on `org.pureswift.Cacao.WindowServer1`:
/// the `GetFocusedWindow` method returns it, and the `FocusChanged` signal
/// carries it each time it changes. Both use the arguments `ssso`: the
/// app's ID, the title, and the menus' bus name and object path. With no
/// window focused, every string is empty; with no menus, the bus name is
/// empty and the path is `/`.
public struct FocusedWindow: Equatable, Sendable {

    /// The window's Wayland `app_id`.
    public var appID: String

    public var title: String

    /// Where the window's menus are, from the appmenu protocol, or nil when
    /// it exports none.
    public var menu: Menu?

    /// A window's menus on the session bus.
    public struct Menu: Equatable, Sendable {

        /// The connection that serves the menus.
        public var service: DBusBusName

        /// The `com.canonical.dbusmenu` object.
        public var path: DBusObjectPath

        public init(service: DBusBusName, path: DBusObjectPath) {
            self.service = service
            self.path = path
        }
    }

    public init(appID: String, title: String, menu: Menu? = nil) {
        self.appID = appID
        self.title = title
        self.menu = menu
    }
}

public extension FocusedWindow {

    static let getFocusedWindow = DBusMember(rawValue: "GetFocusedWindow")!

    static let focusChanged = DBusMember(rawValue: "FocusChanged")!

    /// The signature of the method's reply and of the signal.
    static let signature = DBusSignature(rawValue: "ssso")!

    /// The names of the arguments, for introspection.
    static let argumentNames = ["app_id", "title", "menu_service", "menu_path"]

    /// The signal's identity, for emitting it.
    static let focusChangedSignal = DBusMessage.Signal(
        path: ShellDBus.windowServerPath,
        interface: ShellDBus.windowServerInterface,
        name: focusChanged
    )

    /// The arguments for a focused window, or for none.
    static func arguments(for window: FocusedWindow?) -> [DBusMessageArgument] {
        [
            .string(window?.appID ?? ""),
            .string(window?.title ?? ""),
            .string(window?.menu?.service.rawValue ?? ""),
            .objectPath(window?.menu?.path ?? DBusObjectPath(rawValue: "/")!),
        ]
    }

    /// Reads the arguments of the method's reply or of the signal. The
    /// outer optional is nil when the arguments aren't the interface's; the
    /// inner one when no window has focus.
    static func parse(_ arguments: [DBusMessageArgument]) -> FocusedWindow?? {
        guard arguments.count == 4,
              case let .string(appID) = arguments[0],
              case let .string(title) = arguments[1],
              case let .string(service) = arguments[2],
              case let .objectPath(path) = arguments[3]
        else {
            return nil
        }
        guard !appID.isEmpty else {
            return .some(nil)
        }
        let menu = DBusBusName(rawValue: service).map { Menu(service: $0, path: path) }
        return .some(FocusedWindow(appID: appID, title: title, menu: menu))
    }
}
