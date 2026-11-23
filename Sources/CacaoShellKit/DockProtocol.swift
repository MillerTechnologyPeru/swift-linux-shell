//
//  DockProtocol.swift
//  CacaoShellKit
//

/// The Swift side of the private dock protocol,
/// `Protocols/cacao-dock-unstable-v1.xml`, shared by the dock and the
/// compositor.
public enum DockProtocol {

    /// The global the compositor advertises.
    public static let managerInterface = "zcacao_dock_manager_v1"

    /// The version both ends implement.
    public static let version: UInt32 = 1

    /// What Exposé shows. The raw values are the protocol's.
    public enum ExposeMode: UInt32, CaseIterable, Sendable {

        /// Every window on the current workspace.
        case allWindows = 0

        /// The windows of one app.
        case appWindows = 1

        /// Windows moved aside to show the desktop.
        case desktop = 2
    }
}
