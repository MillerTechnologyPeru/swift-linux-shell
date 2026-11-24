//
//  StatusNotifierTests.swift
//  CacaoShellKitTests
//
//  The StatusNotifierWatcher and host on a private bus, with a status item
//  of the tests' own on another connection.
//

import DBus
import Foundation
import ShellTestSupport
import Testing
@testable import CacaoShellKit

@Test func itemNames() {
    #expect(StatusNotifierWatcher.itemName(service: "org.example.App", sender: ":1.5") == "org.example.App/StatusNotifierItem")
    #expect(StatusNotifierWatcher.itemName(service: "/org/ayatana/NotificationItem/app", sender: ":1.5") == ":1.5/org/ayatana/NotificationItem/app")
    #expect(StatusNotifierWatcher.itemName(service: "not a name", sender: ":1.5") == nil)
    let split = StatusNotifierWatcher.split(":1.5/org/ayatana/NotificationItem/app")
    #expect(split?.busName.rawValue == ":1.5")
    #expect(split?.path.rawValue == "/org/ayatana/NotificationItem/app")
}

@Suite(.enabled(if: PrivateBus.isAvailable, "Needs dbus-daemon"), .serialized)
struct StatusNotifierTests {

    /// Counts the times an item was activated.
    actor Activations {
        var count = 0
        func add() { count += 1 }
    }

    /// Serves a status item on its own connection.
    private func serveItem(on address: String, title: String, activations: Activations) async throws -> DBusConnection {
        let connection = try await DBusConnection.connect(to: address)
        let item = DBusInterfaceImplementation(
            name: ShellDBus.statusNotifierItemInterface,
            methods: [
                .init(name: DBusMember(rawValue: "Activate")!, inputSignature: DBusSignature(rawValue: "ii")!) { _ in
                    await activations.add()
                    return []
                }
            ],
            properties: [
                .init(name: "Id", type: .string) { .string("test-item") },
                .init(name: "Title", type: .string) { .string(title) },
                .init(name: "IconName", type: .string) { .string("network-wireless") },
                .init(name: "Status", type: .string) { .string("Active") },
            ]
        )
        await connection.export(DBusExportedObject([item]), at: DBusObjectPath(rawValue: "/StatusNotifierItem")!)
        return connection
    }

    private func register(_ connection: DBusConnection, service: String) async throws {
        try await connection.callMethod(
            destination: ShellDBus.statusNotifierWatcherName,
            path: ShellDBus.statusNotifierWatcherPath,
            interface: ShellDBus.statusNotifierWatcherInterface,
            method: DBusMember(rawValue: "RegisterStatusNotifierItem")!,
            arguments: [.string(service)]
        )
    }

    /// The next snapshot that satisfies a condition, or nil after a while.
    private func next(
        _ updates: AsyncStream<[StatusItem]>,
        where condition: @escaping @Sendable ([StatusItem]) -> Bool
    ) async -> [StatusItem]? {
        let waiter = Task {
            for await items in updates where condition(items) {
                return Optional(items)
            }
            return nil
        }
        let timeout = Task {
            try await Task.sleep(for: .seconds(5))
            waiter.cancel()
        }
        let items = await waiter.value
        timeout.cancel()
        return items
    }

    @Test func hostSeesItemsComeAndGo() async throws {
        let bus = try await PrivateBus.start()
        defer { bus.stop() }

        // The menu bar: the watcher and the host share a connection.
        let shell = try await DBusConnection.connect(to: bus.address)
        let watcher = StatusNotifierWatcher(connection: shell)
        #expect(try await watcher.start())
        let host = StatusNotifierHost(connection: shell)
        let updates = try await host.start()

        // An item registering with its object path, as libappindicator does.
        let activations = Activations()
        let app = try await serveItem(on: bus.address, title: "Network", activations: activations)
        try await register(app, service: "/StatusNotifierItem")

        let items = await next(updates) { $0.contains { $0.title == "Network" } }
        let item = try #require(items?.first { $0.title == "Network" })
        #expect(item.itemID == "test-item")
        #expect(item.iconName == "network-wireless")
        #expect(item.status == .active)
        #expect(await watcher.hosts.count == 1)

        try await host.activate(item)
        #expect(await activations.count == 1)

        // The app quits: its item goes away.
        await app.close()
        let after = await next(updates) { items in !items.contains { $0.title == "Network" } }
        #expect(after != nil)
        #expect(await watcher.items.isEmpty)

        await host.stop()
        await watcher.stop()
        await shell.close()
    }

    @Test func secondWatcherDefers() async throws {
        let bus = try await PrivateBus.start()
        defer { bus.stop() }
        let first = try await DBusConnection.connect(to: bus.address)
        let second = try await DBusConnection.connect(to: bus.address)
        #expect(try await StatusNotifierWatcher(connection: first).start())
        #expect(try await StatusNotifierWatcher(connection: second).start() == false)
        await second.close()
        await first.close()
    }
}
