//
//  SystemMenu.swift
//  CacaoMenuBar
//
//  The system menu at the left of the menu bar, the session's actions
//  behind it, and their windows: the confirmation for Log Out, Restart and
//  Shut Down, and Force Quit.
//

import CacaoSDL
import CacaoShellKit
import DBus
import Foundation

/// An action that ends the session or turns the computer off, which asks
/// first.
enum SessionAction: String, Hashable, Codable, Sendable {
    case logOut
    case restart
    case shutDown
}

/// The system menu: the computer's settings, Force Quit, and the session's
/// actions, with the Mac's shortcuts. The window server takes the shortcuts
/// and asks the menu bar to show the dialogs.
struct SystemMenu: View {

    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Menu {
            Button("About This Computer") {
                openWindow(id: SystemActions.aboutWindowID)
            }
            Divider()
            Button("System Settings…") {
                SystemActions.shared.openSettings()
            }
            .disabled(!SystemActions.shared.hasSettings)
            Divider()
            Button {
                openWindow(id: SystemActions.forceQuitWindowID)
            } label: {
                SystemMenuItem(title: "Force Quit…", shortcut: "⌥⌘Esc")
            }
            Divider()
            Button("Sleep") {
                SystemActions.shared.sleep()
            }
            Button("Restart…") {
                openWindow(value: SessionAction.restart)
            }
            Button("Shut Down…") {
                openWindow(value: SessionAction.shutDown)
            }
            Divider()
            // There's no lock screen until phase 9.
            Button { } label: {
                SystemMenuItem(title: "Lock Screen", shortcut: "⌃⌘Q")
            }
            .disabled(true)
            Button {
                openWindow(value: SessionAction.logOut)
            } label: {
                SystemMenuItem(title: "Log Out \(SystemActions.userName)…", shortcut: "⇧⌘Q")
            }
        } label: {
            Image(systemName: "circle.grid.2x2")
        }
        .menuStyle(.borderlessButton)
        .onAppear {
            // For the window server's requests, which come with no view.
            SystemActions.shared.openWindow = openWindow
        }
    }
}

/// A system menu item's title, and its shortcut, which the window server
/// takes; ⌘ is the Super key.
struct SystemMenuItem: View {

    let title: String

    let shortcut: String

    var body: some View {
        HStack(spacing: 6) {
            Text(title)
                .lineLimit(1)
            Spacer(minLength: 16)
            Text(shortcut)
                .foregroundStyle(.secondary)
        }
    }
}

/// Asks before logging out, restarting or shutting down, in the middle of
/// the screen over everything else.
struct SessionConfirmation: View {

    let action: SessionAction

    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
            Text(message)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("Cancel") {
                    dismissWindow()
                }
                .keyboardShortcut(.cancelAction)
                Button(confirm) {
                    dismissWindow()
                    SystemActions.shared.perform(action)
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 420)
    }

    private var title: String {
        switch action {
        case .logOut: "Log out now?"
        case .restart: "Restart now?"
        case .shutDown: "Shut down now?"
        }
    }

    private var message: String {
        switch action {
        case .logOut: "Your apps will quit, and you'll return to the login screen."
        case .restart: "Your apps will quit, and the computer will restart."
        case .shutDown: "Your apps will quit, and the computer will turn off."
        }
    }

    private var confirm: String {
        switch action {
        case .logOut: "Log Out"
        case .restart: "Restart"
        case .shutDown: "Shut Down"
        }
    }
}

/// The running apps, to end one that stopped answering.
struct ForceQuitView: View {

    @Environment(\.dismissWindow) private var dismissWindow

    @State private var apps: [RunningApp] = []

    @State private var selection: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Force Quit Applications")
                .font(.headline)
            Text("If an app doesn't respond, select it and click Force Quit. Unsaved changes are lost.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            VStack(spacing: 0) {
                ForEach(apps) { app in
                    Button {
                        selection = app.id
                    } label: {
                        HStack {
                            Text(app.name)
                            Spacer()
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(selection == app.id ? Color.accentColor.opacity(0.25) : Color.clear)
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            HStack {
                Spacer()
                Button("Cancel") {
                    dismissWindow()
                }
                .keyboardShortcut(.cancelAction)
                Button("Force Quit") {
                    if let selection {
                        SystemActions.shared.forceQuit(appID: selection)
                        apps.removeAll { $0.id == selection }
                        self.selection = nil
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(selection == nil || !SystemActions.shared.canForceQuit)
            }
        }
        .padding(16)
        .onAppear {
            apps = SystemActions.shared.runningApps()
        }
    }
}

/// An app with a window open.
struct RunningApp: Identifiable, Hashable {

    /// Its Wayland `app_id`.
    let id: String

    let name: String
}

/// About this computer: its name and system.
struct AboutView: View {

    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "desktopcomputer")
                .font(.system(size: 48))
            Text(SystemActions.computerName)
                .font(.title)
            Text(SystemActions.systemName)
                .foregroundStyle(.secondary)
            Button("OK") {
                dismissWindow()
            }
            .keyboardShortcut(.defaultAction)
            .padding(.top, 8)
        }
        .padding(24)
        .frame(width: 320)
    }
}

/// What the system menu does: through the window server when it's
/// CacaoWindowServer, and through logind for the computer's power.
@MainActor
final class SystemActions {

    static let shared = SystemActions()

    static let forceQuitWindowID = "force-quit"

    static let aboutWindowID = "about"

    /// Opens the menu bar's windows, for requests from the window server.
    var openWindow: OpenWindowAction?

    /// Every installed app, for the Settings app and apps' names.
    private let installed = DesktopEntry.installed()

    private var connection: DBusConnection?

    private var hasWindowServer = false

    private init() {
        Task {
            await connect()
        }
    }

    // MARK: Names

    /// The user's full name, or their login name.
    static var userName: String {
        // The GECOS field: the name, then a comma before the rest.
        let full = NSFullUserName().split(separator: ",", omittingEmptySubsequences: false).first.map(String.init) ?? ""
        return full.trimmingCharacters(in: .whitespaces).isEmpty ? NSUserName() : full
    }

    static var computerName: String {
        ProcessInfo.processInfo.hostName
    }

    /// The system's name and version, from os-release.
    static var systemName: String {
        for path in ["/etc/os-release", "/usr/lib/os-release"] {
            guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { continue }
            for line in text.split(separator: "\n") where line.hasPrefix("PRETTY_NAME=") {
                return line.dropFirst("PRETTY_NAME=".count).trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            }
        }
        return ProcessInfo.processInfo.operatingSystemVersionString
    }

    // MARK: Apps

    /// The Settings app, from swift-linux-core-apps, if it's installed.
    private var settingsEntry: DesktopEntry? {
        installed.first { $0.commandLine != nil && ($0.id.hasSuffix(".Settings") || $0.name == "Settings" || $0.name == "System Settings") }
    }

    var hasSettings: Bool {
        settingsEntry != nil
    }

    func openSettings() {
        guard let entry = settingsEntry, let commandLine = entry.commandLine else { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = commandLine
        do {
            try process.run()
        } catch {
            print("[CacaoMenuBar] Could not open \(entry.id): \(error)")
        }
    }

    /// The apps with windows open, by name.
    func runningApps() -> [RunningApp] {
        FocusedApp.shared.runningAppIDs.map { appID in
            RunningApp(
                id: appID,
                name: installed.first { $0.matches(appID: appID) }?.name
                    ?? appID.split(separator: ".").last.map(String.init)
                    ?? appID
            )
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// Force Quit needs the window server, which knows each window's
    /// process.
    var canForceQuit: Bool {
        hasWindowServer
    }

    func forceQuit(appID: String) {
        callWindowServer(WindowServerActions.forceQuit, arguments: [.string(appID)])
    }

    // MARK: Requests from the window server

    /// The window server took a shortcut whose dialog the menu bar shows.
    func handle(_ action: WindowServerActions.Action) {
        switch action {
        case .logOut:
            openWindow?(value: SessionAction.logOut)
        case .forceQuit:
            openWindow?(id: Self.forceQuitWindowID)
        }
    }

    // MARK: The session and the computer's power

    func perform(_ action: SessionAction) {
        switch action {
        case .logOut:
            logOut()
        case .restart:
            callLogind("Reboot")
        case .shutDown:
            callLogind("PowerOff")
        }
    }

    func sleep() {
        callLogind("Suspend")
    }

    /// Ends the session: the window server quits when it's CacaoWindowServer;
    /// under another compositor, logind ends the session.
    private func logOut() {
        if hasWindowServer {
            callWindowServer(WindowServerActions.logOut, arguments: [])
            return
        }
        guard let session = ProcessInfo.processInfo.environment["XDG_SESSION_ID"] else {
            print("[CacaoMenuBar] Can't log out: no window server and no logind session")
            return
        }
        callLogind("TerminateSession", arguments: [.string(session)])
    }

    private func connect() async {
        do {
            let connection = try await DBusConnection.connect(to: .session)
            self.connection = connection
            hasWindowServer = try await connection.nameHasOwner(ShellDBus.windowServerName)
        } catch {
            print("[CacaoMenuBar] The system menu has no session bus: \(error)")
        }
    }

    private func callWindowServer(_ method: DBusMember, arguments: [DBusMessageArgument]) {
        guard let connection else { return }
        Task {
            do {
                try await connection.callMethod(
                    destination: ShellDBus.windowServerName,
                    path: ShellDBus.windowServerPath,
                    interface: ShellDBus.windowServerInterface,
                    method: method,
                    arguments: arguments
                )
            } catch {
                print("[CacaoMenuBar] The window server didn't do \(method.rawValue): \(error)")
            }
        }
    }

    /// Calls a method of logind's manager on the system bus. Polkit lets
    /// the active local session do these without asking.
    private func callLogind(_ method: String, arguments: [DBusMessageArgument]? = nil) {
        // Not interactive: there's no polkit agent to ask until phase 9.
        let arguments = arguments ?? [.boolean(false)]
        Task {
            do {
                let system = try await DBusConnection.connect(to: .system)
                try await system.callMethod(
                    destination: DBusBusName(rawValue: "org.freedesktop.login1")!,
                    path: DBusObjectPath(rawValue: "/org/freedesktop/login1")!,
                    interface: DBusInterface(rawValue: "org.freedesktop.login1.Manager")!,
                    method: DBusMember(rawValue: method)!,
                    arguments: arguments
                )
                await system.close()
            } catch {
                print("[CacaoMenuBar] logind didn't do \(method): \(error)")
            }
        }
    }
}
