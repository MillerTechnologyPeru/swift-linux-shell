//
//  AppMenuRegistrarTests.swift
//  CacaoShellKitTests
//

import DBus
import Foundation
import ShellTestSupport
import Testing
@testable import CacaoShellKit

@Suite(.enabled(if: PrivateBus.isAvailable, "Needs dbus-daemon"), .serialized)
struct AppMenuRegistrarTests {

    private func call(_ connection: DBusConnection, _ method: String, _ arguments: [DBusMessageArgument]) async throws -> [DBusMessageArgument] {
        try await connection.callMethod(
            destination: ShellDBus.appMenuRegistrarName,
            path: ShellDBus.appMenuRegistrarPath,
            interface: ShellDBus.appMenuRegistrarInterface,
            method: DBusMember(rawValue: method)!,
            arguments: arguments
        )
    }

    @Test func registersAndForgetsWindows() async throws {
        let bus = try await PrivateBus.start()
        defer { bus.stop() }
        let shell = try await DBusConnection.connect(to: bus.address)
        let registrar = AppMenuRegistrar(connection: shell)
        #expect(try await registrar.start())

        // What apps check before hiding their own menu bar.
        let app = try await DBusConnection.connect(to: bus.address)
        #expect(try await app.nameHasOwner(ShellDBus.appMenuRegistrarName))

        let path = DBusObjectPath(rawValue: "/MenuBar")!
        _ = try await call(app, "RegisterWindow", [.uint32(42), .objectPath(path)])
        let menu = try await call(app, "GetMenuForWindow", [.uint32(42)])
        #expect(menu.count == 2)
        #expect(menu.last == .objectPath(path))
        if case let .string(service)? = menu.first {
            #expect(service == (await app.uniqueName)?.rawValue)
        } else {
            Issue.record("GetMenuForWindow returned \(menu)")
        }

        await #expect(throws: DBusError.self) {
            try await call(app, "GetMenuForWindow", [.uint32(7)])
        }

        // The app quits: its windows' menus are forgotten.
        await app.close()
        for _ in 0 ..< 50 {
            if await registrar.windows.isEmpty { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(await registrar.windows.isEmpty)

        await registrar.stop()
        await shell.close()
    }

    @Test func secondRegistrarDefers() async throws {
        let bus = try await PrivateBus.start()
        defer { bus.stop() }
        let first = try await DBusConnection.connect(to: bus.address)
        let second = try await DBusConnection.connect(to: bus.address)
        #expect(try await AppMenuRegistrar(connection: first).start())
        #expect(try await AppMenuRegistrar(connection: second).start() == false)
        await second.close()
        await first.close()
    }
}
