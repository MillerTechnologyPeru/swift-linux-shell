//
//  LauncherEntriesTests.swift
//  CacaoShellKitTests
//
//  Launcher entries on a private bus, from an app on another connection.
//

import DBus
import Foundation
import ShellTestSupport
import Testing
@testable import CacaoShellKit

@Test func desktopIDs() {
    #expect(LauncherEntries.desktopID(appURI: "application://firefox.desktop") == "firefox")
    #expect(LauncherEntries.desktopID(appURI: "application://org.gnome.Nautilus.desktop") == "org.gnome.Nautilus")
    #expect(LauncherEntries.desktopID(appURI: "application://") == nil)
    #expect(LauncherEntries.desktopID(appURI: "file:///usr/share/applications/firefox.desktop") == nil)
}

@Test func badgeText() {
    var state = LauncherEntryState()
    #expect(state.badge == nil)
    #expect(state.isEmpty)
    state.count = 7
    #expect(state.badge == nil)
    state.isCountVisible = true
    #expect(state.badge == "7")
    state.count = 1200
    #expect(state.badge == "999+")
}

@Suite(.enabled(if: PrivateBus.isAvailable, "Needs dbus-daemon"), .serialized)
struct LauncherEntriesTests {

    /// Emits an `Update` signal, as an app does.
    private func update(_ app: DBusConnection, uri: String, _ properties: [(String, DBusMessageArgument)]) async throws {
        let entries = properties.map { DBusMessageArgument.Dictionary.Entry(key: .string($0.0), value: .variant(.init($0.1))) }
        try await app.emit(
            DBusMessage.Signal(
                path: DBusObjectPath(rawValue: "/com/canonical/unity/launcherentry/1")!,
                interface: ShellDBus.launcherEntryInterface,
                name: DBusMember(rawValue: "Update")!
            ),
            arguments: [
                .string(uri),
                .dictionary(DBusMessageArgument.Dictionary(keyType: .string, valueType: .variant, entries)!),
            ]
        )
    }

    /// The next snapshot that satisfies a condition, or nil after a while.
    private func next(
        _ updates: AsyncStream<[String: LauncherEntryState]>,
        where condition: @escaping @Sendable ([String: LauncherEntryState]) -> Bool
    ) async -> [String: LauncherEntryState]? {
        let waiter = Task {
            for await entries in updates where condition(entries) {
                return Optional(entries)
            }
            return nil
        }
        let timeout = Task {
            try await Task.sleep(for: .seconds(5))
            waiter.cancel()
        }
        let entries = await waiter.value
        timeout.cancel()
        return entries
    }

    @Test func updatesMergeAndGoWithTheApp() async throws {
        let bus = try await PrivateBus.start()
        defer { bus.stop() }
        let dock = try await DBusConnection.connect(to: bus.address)
        let launcherEntries = LauncherEntries(connection: dock)
        let updates = try await launcherEntries.start()
        let app = try await DBusConnection.connect(to: bus.address)

        try await update(app, uri: "application://org.example.Mail.desktop", [
            ("count", .int64(3)),
            ("count-visible", .boolean(true)),
        ])
        let first = await next(updates) { $0["org.example.Mail"]?.badge == "3" }
        #expect(first != nil)

        // A later update changes only what it names.
        try await update(app, uri: "application://org.example.Mail.desktop", [
            ("progress", .double(0.25)),
            ("progress-visible", .boolean(true)),
            ("urgent", .boolean(true)),
        ])
        let second = await next(updates) { $0["org.example.Mail"]?.isUrgent == true }
        let state = try #require(second?["org.example.Mail"])
        #expect(state.badge == "3")
        #expect(state.progress == 0.25)
        #expect(state.isProgressVisible)

        // The app quits: its badge goes with it.
        await app.close()
        let gone = await next(updates) { $0["org.example.Mail"] == nil }
        #expect(gone != nil)

        await launcherEntries.stop()
        await dock.close()
    }
}
