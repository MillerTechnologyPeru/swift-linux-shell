//
//  main.swift
//  CacaoSettings
//
//  The settings daemon: no UI, the only settings provider on the system.
//  It serves appearance settings to apps as the portal's Settings backend,
//  and takes changes from the shell on its own interface.
//
//  Started by D-Bus activation (Data/org.freedesktop.impl.portal.desktop.cacao.service)
//  or by the session.
//

import CacaoShellKit
import DBus
import Foundation

func log(_ message: String) {
    // Standard error, which is unbuffered, so lines survive the process being killed.
    FileHandle.standardError.write(Data("[CacaoSettings] \(message)\n".utf8))
}

let store = SettingsStore()
log("Settings in \(store.fileURL.path)")

let connection: DBusConnection
do {
    connection = try await DBusConnection.connect(to: .session)
} catch {
    log("Could not connect to the session bus: \(error)")
    exit(EXIT_FAILURE)
}

let portal = PortalSettings(store: store)
await portal.export(on: connection)

for name in [ShellDBus.portalBackendName, ShellDBus.settingsName] {
    do {
        let result = try await connection.requestName(name)
        guard result == .primaryOwner || result == .alreadyOwner else {
            // Two providers that disagree is the failure this service exists
            // to prevent, so a second copy exits.
            log("\(name.rawValue) is owned by another process")
            exit(EXIT_FAILURE)
        }
    } catch {
        log("Could not own \(name.rawValue): \(error)")
        exit(EXIT_FAILURE)
    }
}

log("Serving \(ShellDBus.portalSettingsBackendInterface.rawValue) as \(ShellDBus.portalBackendName.rawValue)")

// Method calls are answered on the connection's own read loop.
while await connection.isConnected {
    try? await Task.sleep(for: .seconds(60))
}
log("Disconnected from the session bus")
