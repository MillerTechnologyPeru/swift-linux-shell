//
//  WindowPolicy.swift
//  CacaoWindowServer
//

import CWLRoots
import CacaoShellKit

/// Where windows go and which one has focus. Each form factor has its own
/// policy, so tablet and phone modes add a policy instead of changing the
/// desktop's.
@MainActor
protocol WindowPolicy: AnyObject {

    /// A window appeared on screen.
    func windowMapped(_ window: Window, server: WindowServer)

    /// A window left the screen, or is about to be destroyed.
    func windowUnmapped(_ window: Window, server: WindowServer)

    /// The user pressed a pointer button over a window.
    func windowClicked(_ window: Window, server: WindowServer)

    /// The menu bar or dock reserved a different area.
    func usableAreaChanged(_ area: CWLBox, server: WindowServer)
}

@MainActor
func makePolicy(for formFactor: FormFactor) -> any WindowPolicy {
    switch formFactor {
    case .desktop:
        return DesktopPolicy()
    case .tablet, .phone:
        // Desktop is finished before the other modes start.
        log("\(formFactor) mode is not implemented yet; using desktop")
        return DesktopPolicy()
    }
}
