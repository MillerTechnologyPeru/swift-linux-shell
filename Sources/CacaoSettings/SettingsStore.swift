//
//  SettingsStore.swift
//  CacaoSettings
//

import CacaoShellKit
import Foundation

/// The appearance settings, kept in
/// `$XDG_CONFIG_HOME/cacao/settings.json`.
actor SettingsStore {

    let fileURL: URL

    private(set) var settings: AppearanceSettings

    init(fileURL: URL = SettingsStore.defaultFileURL()) {
        self.fileURL = fileURL
        if let data = try? Data(contentsOf: fileURL),
           let settings = try? JSONDecoder().decode(AppearanceSettings.self, from: data) {
            self.settings = settings
        } else {
            self.settings = AppearanceSettings()
        }
    }

    /// Replaces the settings, saves them, and returns what changed.
    func update(_ body: (inout AppearanceSettings) -> Void) throws -> [(namespace: String, key: String, value: PortalValue)] {
        let old = settings
        var new = settings
        body(&new)
        guard new != old else {
            return []
        }
        settings = new
        try save()
        return new.changes(from: old)
    }

    private func save() throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(settings).write(to: fileURL, options: .atomic)
    }

    static func defaultFileURL(environment: [String: String] = ProcessInfo.processInfo.environment) -> URL {
        let home = environment["HOME"] ?? NSHomeDirectory()
        let configHome = environment["XDG_CONFIG_HOME"].flatMap { $0.isEmpty ? nil : $0 } ?? home + "/.config"
        return URL(fileURLWithPath: configHome)
            .appendingPathComponent("cacao", isDirectory: true)
            .appendingPathComponent("settings.json")
    }
}
