//
//  LauncherBadges.swift
//  CacaoDock
//

import CacaoSDL
import CacaoShellKit
import DBus
import Foundation

/// Apps' badges, progress and urgency for their launchers, from
/// `com.canonical.Unity.LauncherEntry`, as other docks read them.
@MainActor
final class LauncherBadges: ObservableObject {

    static let shared = LauncherBadges()

    /// Each app's state, by desktop file ID.
    @Published private(set) var entries = [String: LauncherEntryState]()

    private var launcherEntries: LauncherEntries?

    private init() {
        Task {
            await start()
        }
    }

    /// The state for an app, by its desktop entry or its `app_id`.
    func state(for entry: DesktopEntry) -> LauncherEntryState? {
        entries[entry.id] ?? entries.first { entry.matches(appID: $0.key) }?.value
    }

    func state(forAppID appID: String) -> LauncherEntryState? {
        entries[appID] ?? entries.first { $0.key.lowercased() == appID.lowercased() }?.value
    }

    private func start() async {
        do {
            let connection = try await DBusConnection.connect(to: .session)
            let launcherEntries = LauncherEntries(connection: connection)
            self.launcherEntries = launcherEntries
            let updates = try await launcherEntries.start()
            for await entries in updates {
                self.entries = entries
            }
        } catch {
            print("[CacaoDock] Apps' badges aren't available: \(error)")
        }
    }
}
