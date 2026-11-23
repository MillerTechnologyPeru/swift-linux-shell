//
//  AppearanceSettingsTests.swift
//  CacaoShellKitTests
//

import DBus
import Testing
@testable import CacaoShellKit

@Suite struct AppearanceSettingsTests {

    @Test func servesStandardKeys() {
        let settings = AppearanceSettings(colorScheme: .dark)
        #expect(settings.portalValue(namespace: "org.freedesktop.appearance", key: "color-scheme") == .uint32(1))
        #expect(settings.portalValue(namespace: "org.gnome.desktop.interface", key: "color-scheme") == .string("prefer-dark"))
        #expect(settings.portalValue(namespace: "org.freedesktop.appearance", key: "missing") == nil)
    }

    @Test func readAllPatterns() {
        let settings = AppearanceSettings()
        #expect(settings.portalValues(matching: []).count == 3)
        #expect(Set(settings.portalValues(matching: ["org.gnome.*"]).keys) == ["org.gnome.desktop.interface", "org.gnome.desktop.wm.preferences"])
        #expect(Set(settings.portalValues(matching: ["org.freedesktop.appearance"]).keys) == ["org.freedesktop.appearance"])
    }

    @Test func changesListEveryAffectedKey() {
        let old = AppearanceSettings(colorScheme: .light)
        let new = AppearanceSettings(colorScheme: .dark)
        let changes = new.changes(from: old)
        #expect(changes.map { "\($0.namespace) \($0.key)" } == [
            "org.freedesktop.appearance color-scheme",
            "org.gnome.desktop.interface color-scheme",
        ])
    }

    @Test func readAllSignature() throws {
        let argument = try AppearanceSettings.readAllArgument(AppearanceSettings().portalValues)
        #expect(String(argument.type) == "a{sa{sv}}")
    }

    @Test func accentColorIsStructure() {
        #expect(String(PortalValue.color(1, 0, 0).messageArgument.type) == "(ddd)")
    }
}
