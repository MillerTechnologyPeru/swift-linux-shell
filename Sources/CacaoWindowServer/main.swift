//
//  main.swift
//  CacaoWindowServer
//
//  The compositor. Until it replaces sway (phase 7), it runs nested in an
//  existing Wayland or X11 session for development, or on a VT.
//
//  Usage: CacaoWindowServer [--form-factor desktop|tablet|phone] [-s command]
//

import CWLRoots
import CacaoShellKit
import Foundation

var formFactor = FormFactor.desktop
var startupCommand: String?

var arguments = CommandLine.arguments.dropFirst()
while let argument = arguments.popFirst() {
    switch argument {
    case "--form-factor":
        guard let value = arguments.popFirst(), let parsed = FormFactor(rawValue: value) else {
            print("--form-factor takes desktop, tablet or phone")
            exit(EXIT_FAILURE)
        }
        formFactor = parsed
    case "-s", "--startup":
        guard let command = arguments.popFirst() else {
            print("\(argument) takes a command")
            exit(EXIT_FAILURE)
        }
        startupCommand = command
    case "-h", "--help":
        print("Usage: CacaoWindowServer [--form-factor desktop|tablet|phone] [-s command]")
        exit(EXIT_SUCCESS)
    default:
        print("Unknown argument \(argument)")
        exit(EXIT_FAILURE)
    }
}

#if os(Linux)
log("wlroots \(cwl_wlroots_version().map { String(cString: $0) } ?? "unknown")")

let server = WindowServer(policy: makePolicy(for: formFactor))
do {
    let socket = try server.start()
    log("Listening on WAYLAND_DISPLAY=\(socket)")
} catch {
    log("\(error)")
    exit(EXIT_FAILURE)
}

if server.hasSeatSession {
    // Services D-Bus starts, such as xdg-desktop-portal, need the session's
    // display and desktop name before anything asks for them, as the title
    // bars' appearance does next.
    let update = Process()
    update.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    update.arguments = ["dbus-update-activation-environment", "--systemd", "WAYLAND_DISPLAY", "XDG_CURRENT_DESKTOP", "XDG_SESSION_TYPE"]
    do {
        try update.run()
        update.waitUntilExit()
    } catch {
        log("Could not update the D-Bus activation environment: \(error)")
    }
}

// The desktop's look, for the title bars the window server draws.
server.followAppearance()

if let startupCommand {
    // WAYLAND_DISPLAY is already set, so the command connects to this server.
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/sh")
    process.arguments = ["-c", startupCommand]
    do {
        try process.run()
    } catch {
        log("Could not run \(startupCommand): \(error)")
    }
}

server.run()
server.shutDown()
#else
print("CacaoWindowServer runs on Linux only.")
exit(EXIT_FAILURE)
#endif
