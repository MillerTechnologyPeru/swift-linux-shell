//
//  FormFactor.swift
//  CacaoShellKit
//

/// How a screen is presented: the compositor picks its window policy from
/// this, and each shell process picks its presentation.
///
/// The settings service holds one for each screen. Only desktop is
/// implemented; tablet and phone follow once the desktop is complete.
public enum FormFactor: String, Codable, CaseIterable, Sendable {

    /// Free-floating windows with title bars, a menu bar and a dock.
    case desktop

    /// Full-screen or split apps, a status bar and a swipe-up dock.
    case tablet

    /// One full-screen app, a status bar and a home gesture.
    case phone
}

public extension FormFactor {

    /// Whether windows float and have title bars and window buttons.
    var hasFloatingWindows: Bool {
        self == .desktop
    }

    /// Whether the top bar shows app menus all the time. In tablet mode they
    /// are revealed from the top edge, and phones show none.
    var showsMenusInTopBar: Bool {
        self == .desktop
    }

    /// Whether there is a dock at all.
    var hasDock: Bool {
        self != .phone
    }
}
