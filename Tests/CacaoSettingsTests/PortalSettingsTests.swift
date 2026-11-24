//
//  PortalSettingsTests.swift
//  CacaoSettingsTests
//
//  The settings service on a real bus: it serves the portal Settings
//  backend from one connection, and another connection calls it the way
//  xdg-desktop-portal and the shell do.
//

import CacaoShellKit
import DBus
import Foundation
import ShellTestSupport
import Testing
@testable import CacaoSettings

@Suite(.enabled(if: PrivateBus.isAvailable, "Needs dbus-daemon"), .serialized)
struct PortalSettingsTests {

    /// Runs `body` with the service on a private bus, its settings in a
    /// temporary file, and a client connection.
    private func withService(
        _ body: (_ client: DBusConnection, _ store: SettingsStore) async throws -> Void
    ) async throws {
        let bus = try await PrivateBus.start()
        defer { bus.stop() }
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("cacao-settings-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: file) }

        let store = SettingsStore(fileURL: file)
        let service = try await DBusConnection.connect(to: bus.address)
        await PortalSettings(store: store).export(on: service)
        try await service.requestName(ShellDBus.portalBackendName)
        try await service.requestName(ShellDBus.settingsName)

        let client = try await DBusConnection.connect(to: bus.address)
        do {
            try await body(client, store)
        } catch {
            await client.close()
            await service.close()
            throw error
        }
        await client.close()
        await service.close()
    }

    private func read(_ client: DBusConnection, _ namespace: String, _ key: String) async throws -> DBusMessageArgument? {
        let reply = try await client.callMethod(
            destination: ShellDBus.portalBackendName,
            path: ShellDBus.portalPath,
            interface: ShellDBus.portalSettingsBackendInterface,
            method: DBusMember(rawValue: "Read")!,
            arguments: [.string(namespace), .string(key)]
        )
        return reply.first?.variantValue
    }

    @Test func readsAKey() async throws {
        try await withService { client, _ in
            let scheme = try await read(client, "org.freedesktop.appearance", "color-scheme")
            #expect(scheme == .uint32(0))
            let layout = try await read(client, "org.gnome.desktop.wm.preferences", "button-layout")
            #expect(layout == .string("close,minimize,maximize:"))
        }
    }

    @Test func unknownKeyIsNotFound() async throws {
        try await withService { client, _ in
            let error = await #expect(throws: DBusError.self) {
                try await read(client, "org.freedesktop.appearance", "no-such-key")
            }
            #expect(error?.name.rawValue == "org.freedesktop.portal.Error.NotFound")
        }
    }

    @Test func readsAllMatchingNamespaces() async throws {
        try await withService { client, _ in
            let reply = try await client.callMethod(
                destination: ShellDBus.portalBackendName,
                path: ShellDBus.portalPath,
                interface: ShellDBus.portalSettingsBackendInterface,
                method: DBusMember(rawValue: "ReadAll")!,
                arguments: [.array(DBusMessageArgument.Array(type: .string, [.string("org.gnome.*")])!)]
            )
            guard case let .dictionary(namespaces)? = reply.first else {
                Issue.record("ReadAll returned \(reply)")
                return
            }
            #expect(Set(namespaces.compactMap(\.key.stringValue)) == ["org.gnome.desktop.interface", "org.gnome.desktop.wm.preferences"])
        }
    }

    @Test func servesVersion2() async throws {
        try await withService { client, _ in
            let version = try await client.getProperty(
                destination: ShellDBus.portalBackendName,
                path: ShellDBus.portalPath,
                interface: ShellDBus.portalSettingsBackendInterface,
                name: "version"
            )
            #expect(version == .uint32(2))
        }
    }

    @Test func setSavesAndSignalsTheChange() async throws {
        try await withService { client, store in
            let changes = try await client.signals(
                interface: ShellDBus.portalSettingsBackendInterface,
                member: DBusMember(rawValue: "SettingChanged")!,
                path: ShellDBus.portalPath
            )

            try await client.callMethod(
                destination: ShellDBus.settingsName,
                path: ShellDBus.settingsPath,
                interface: ShellDBus.settingsInterface,
                method: DBusMember(rawValue: "Set")!,
                arguments: [
                    .string("org.freedesktop.appearance"),
                    .string("color-scheme"),
                    .variant(DBusMessageArgument.Variant(.uint32(1))),
                ]
            )

            let scheme = try await read(client, "org.freedesktop.appearance", "color-scheme")
            #expect(scheme == .uint32(1))
            let stored = await store.settings.colorScheme
            #expect(stored == .dark)
            let saved = try JSONDecoder().decode(AppearanceSettings.self, from: Data(contentsOf: store.fileURL))
            #expect(saved.colorScheme == .dark)

            // Dark mode changes the standard key and GNOME's. Cancelling the
            // collector after a while ends the stream, so a missing signal
            // fails the test instead of hanging it.
            let collector = Task {
                var received = [String]()
                for await message in changes {
                    guard message.arguments.count == 3,
                          case let .string(namespace) = message.arguments[0],
                          case let .string(key) = message.arguments[1]
                    else { continue }
                    received.append("\(namespace) \(key)")
                    if received.count == 2 { break }
                }
                return received
            }
            let timeout = Task {
                try await Task.sleep(for: .seconds(5))
                collector.cancel()
            }
            let received = await collector.value
            timeout.cancel()
            #expect(received == [
                "org.freedesktop.appearance color-scheme",
                "org.gnome.desktop.interface color-scheme",
            ])
        }
    }
}
