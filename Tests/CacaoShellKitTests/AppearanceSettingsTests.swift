//
//  AppearanceSettingsTests.swift
//  CacaoShellKitTests
//

import DBus
import Foundation
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
        #expect(settings.portalValues(matching: []).count == 4)
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

    @Test func effectsAreServedForTheShellAndGTK() {
        let settings = AppearanceSettings(effects: false)
        #expect(settings.portalValue(namespace: AppearanceSettings.cacaoNamespace, key: "effects") == .bool(false))
        #expect(settings.portalValue(namespace: "org.gnome.desktop.interface", key: "enable-animations") == .bool(false))
        let changes = AppearanceSettings(effects: true).changes(from: settings)
        #expect(changes.map { "\($0.namespace) \($0.key)" } == [
            "org.gnome.desktop.interface enable-animations",
            "org.pureswift.cacao effects",
        ])
    }

    @Test func savedSettingsWithoutNewKeysKeepTheirValues() throws {
        // Saved before effects existed.
        let json = #"{"colorScheme":1,"accentColor":{"red":1,"green":0,"blue":0},"contrast":0,"buttonLayout":"close:","fontName":"Inter 11","monospaceFontName":"JetBrains Mono 10","iconTheme":"elementary","cursorTheme":"Adwaita","cursorSize":32,"formFactors":{}}"#
        let settings = try JSONDecoder().decode(AppearanceSettings.self, from: Data(json.utf8))
        #expect(settings.colorScheme == .dark)
        #expect(settings.fontName == "Inter 11")
        #expect(settings.cursorSize == 32)
        #expect(settings.effects == AppearanceSettings.defaultEffects)
        // And what's saved now reads back the same.
        let again = try JSONDecoder().decode(AppearanceSettings.self, from: JSONEncoder().encode(settings))
        #expect(again == settings)
    }

    @Test func accentColorIsStructure() {
        #expect(String(PortalValue.color(1, 0, 0).messageArgument.type) == "(ddd)")
    }
}
