//
//  NotificationServerTests.swift
//  CacaoShellKitTests
//
//  The notification server on a private bus, with an app on another
//  connection posting and closing notifications.
//

import DBus
import Foundation
import ShellTestSupport
import Testing
@testable import CacaoShellKit

@Suite(.enabled(if: PrivateBus.isAvailable, "Needs dbus-daemon"), .serialized)
struct NotificationServerTests {

    /// `Notify`'s arguments.
    private func notify(
        _ app: DBusConnection,
        summary: String,
        body: String = "",
        replaces: UInt32 = 0,
        actions: [String] = [],
        urgency: UInt8? = nil,
        timeout: Int32 = -1
    ) async throws -> UInt32 {
        var hints: [DBusMessageArgument.Dictionary.Entry] = []
        if let urgency {
            hints.append(.init(key: .string("urgency"), value: .variant(.init(.byte(urgency)))))
        }
        let reply = try await app.callMethod(
            destination: ShellDBus.notificationsName,
            path: ShellDBus.notificationsPath,
            interface: ShellDBus.notificationsInterface,
            method: DBusMember(rawValue: "Notify")!,
            arguments: [
                .string("Tests"),
                .uint32(replaces),
                .string(""),
                .string(summary),
                .string(body),
                .array(DBusMessageArgument.Array(type: .string, actions.map { .string($0) })!),
                .dictionary(DBusMessageArgument.Dictionary(keyType: .string, valueType: .variant, hints)!),
                .int32(timeout),
            ]
        )
        guard case let .uint32(id)? = reply.first else {
            Issue.record("Notify returned \(reply)")
            return 0
        }
        return id
    }

    /// The next event, or nil after a while.
    private func next(_ events: AsyncStream<NotificationServer.Event>) async -> NotificationServer.Event? {
        let waiter = Task {
            for await event in events {
                return Optional(event)
            }
            return nil
        }
        let timeout = Task {
            try await Task.sleep(for: .seconds(5))
            waiter.cancel()
        }
        let event = await waiter.value
        timeout.cancel()
        return event
    }

    /// The next signal's arguments, or nil after a while.
    private func next(_ signals: AsyncStream<DBusMessage>) async -> [DBusMessageArgument]? {
        let waiter = Task {
            for await signal in signals {
                return Optional(signal.arguments)
            }
            return nil
        }
        let timeout = Task {
            try await Task.sleep(for: .seconds(5))
            waiter.cancel()
        }
        let arguments = await waiter.value
        timeout.cancel()
        return arguments
    }

    @Test func postReplaceAndClose() async throws {
        let bus = try await PrivateBus.start()
        defer { bus.stop() }
        let shell = try await DBusConnection.connect(to: bus.address)
        let server = NotificationServer(connection: shell)
        #expect(try await server.start())
        let app = try await DBusConnection.connect(to: bus.address)
        let closed = try await app.signals(
            interface: ShellDBus.notificationsInterface,
            member: DBusMember(rawValue: "NotificationClosed")!
        )

        let id = try await notify(app, summary: "Download finished", body: "report.pdf", actions: ["default", "Open", "show", "Show in Files"], urgency: 2)
        guard case let .posted(notification)? = await next(server.events) else {
            Issue.record("No notification posted")
            return
        }
        #expect(notification.id == id)
        #expect(notification.appName == "Tests")
        #expect(notification.summary == "Download finished")
        #expect(notification.body == "report.pdf")
        #expect(notification.hasDefaultAction)
        #expect(notification.buttons == [.init(key: "show", label: "Show in Files")])
        #expect(notification.urgency == .critical)

        // The same ID, with new text.
        let replaced = try await notify(app, summary: "Download finished", body: "report-2.pdf", replaces: id)
        #expect(replaced == id)
        guard case let .posted(update)? = await next(server.events) else {
            Issue.record("No update posted")
            return
        }
        #expect(update.body == "report-2.pdf")

        // The app closes it.
        try await app.callMethod(
            destination: ShellDBus.notificationsName,
            path: ShellDBus.notificationsPath,
            interface: ShellDBus.notificationsInterface,
            method: DBusMember(rawValue: "CloseNotification")!,
            arguments: [.uint32(id)]
        )
        guard case let .closed(closedID)? = await next(server.events) else {
            Issue.record("Not closed")
            return
        }
        #expect(closedID == id)
        let reason = await next(closed)
        #expect(reason == [.uint32(id), .uint32(NotificationCloseReason.closedByCall.rawValue)])
        #expect(await server.open.isEmpty)

        await app.close()
        await shell.close()
    }

    @Test func actionInvokedClosesAsDismissed() async throws {
        let bus = try await PrivateBus.start()
        defer { bus.stop() }
        let shell = try await DBusConnection.connect(to: bus.address)
        let server = NotificationServer(connection: shell)
        #expect(try await server.start())
        let app = try await DBusConnection.connect(to: bus.address)
        let invoked = try await app.signals(
            interface: ShellDBus.notificationsInterface,
            member: DBusMember(rawValue: "ActionInvoked")!
        )
        let closed = try await app.signals(
            interface: ShellDBus.notificationsInterface,
            member: DBusMember(rawValue: "NotificationClosed")!
        )

        let id = try await notify(app, summary: "Meeting", actions: ["join", "Join"])
        _ = await next(server.events)
        await server.invoke(id, action: "join")
        #expect(await next(invoked) == [.uint32(id), .string("join")])
        #expect(await next(closed) == [.uint32(id), .uint32(NotificationCloseReason.dismissed.rawValue)])

        await app.close()
        await shell.close()
    }

    @Test func serverInformationAndCapabilities() async throws {
        let bus = try await PrivateBus.start()
        defer { bus.stop() }
        let shell = try await DBusConnection.connect(to: bus.address)
        #expect(try await NotificationServer(connection: shell).start())
        let app = try await DBusConnection.connect(to: bus.address)
        let information = try await app.callMethod(
            destination: ShellDBus.notificationsName,
            path: ShellDBus.notificationsPath,
            interface: ShellDBus.notificationsInterface,
            method: DBusMember(rawValue: "GetServerInformation")!
        )
        #expect(information.last == .string("1.2"))
        let capabilities = try await app.callMethod(
            destination: ShellDBus.notificationsName,
            path: ShellDBus.notificationsPath,
            interface: ShellDBus.notificationsInterface,
            method: DBusMember(rawValue: "GetCapabilities")!
        )
        guard case let .array(names)? = capabilities.first else {
            Issue.record("No capabilities")
            return
        }
        #expect(names.compactMap(\.stringValue) == NotificationServer.capabilities)

        // A second server defers to the first.
        let other = try await DBusConnection.connect(to: bus.address)
        #expect(try await NotificationServer(connection: other).start() == false)

        await other.close()
        await app.close()
        await shell.close()
    }
}
