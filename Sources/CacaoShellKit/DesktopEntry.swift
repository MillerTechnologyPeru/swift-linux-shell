//
//  DesktopEntry.swift
//  CacaoShellKit
//

import Foundation

/// An application's freedesktop desktop entry: what the dock shows for a
/// launcher, and how running windows are matched to it.
///
/// Only the `[Desktop Entry]` group is read, and localized keys are ignored
/// for now.
public struct DesktopEntry: Equatable, Hashable, Sendable {

    /// The desktop file ID: the file's path below `applications/` with `/`
    /// replaced by `-` and without `.desktop`. Wayland `app_id`s usually
    /// match it.
    public let id: String

    public var name: String

    public var genericName: String?

    public var comment: String?

    /// An icon name to look up in the icon theme, or an absolute path.
    public var icon: String?

    /// The command line, with field codes such as `%f` still in it.
    public var exec: String?

    /// The `app_id` or X11 class the app's windows have, when it differs
    /// from the desktop file ID.
    public var startupWMClass: String?

    public var categories: [String]

    /// Whether the entry is hidden from launchers.
    public var noDisplay: Bool

    /// Whether the entry is deleted, as when a user overrides a system one.
    public var hidden: Bool

    public var terminal: Bool

    public init(
        id: String,
        name: String,
        genericName: String? = nil,
        comment: String? = nil,
        icon: String? = nil,
        exec: String? = nil,
        startupWMClass: String? = nil,
        categories: [String] = [],
        noDisplay: Bool = false,
        hidden: Bool = false,
        terminal: Bool = false
    ) {
        self.id = id
        self.name = name
        self.genericName = genericName
        self.comment = comment
        self.icon = icon
        self.exec = exec
        self.startupWMClass = startupWMClass
        self.categories = categories
        self.noDisplay = noDisplay
        self.hidden = hidden
        self.terminal = terminal
    }
}

// MARK: - Parsing

public extension DesktopEntry {

    /// Parses the contents of a desktop file. Returns nil if it is not an
    /// application or has no name.
    init?(id: String, contents: String) {
        var values = [String: String]()
        var inMainGroup = false
        for rawLine in contents.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") {
                continue
            }
            if line.hasPrefix("[") {
                inMainGroup = line == "[Desktop Entry]"
                continue
            }
            guard inMainGroup, let separator = line.firstIndex(of: "=") else {
                continue
            }
            let key = line[..<separator].trimmingCharacters(in: .whitespaces)
            // Localized keys such as Name[es] are skipped.
            guard key.contains("[") == false else {
                continue
            }
            let value = line[line.index(after: separator)...].trimmingCharacters(in: .whitespaces)
            values[key] = Self.unescape(value)
        }
        guard values["Type"] == "Application", let name = values["Name"] else {
            return nil
        }
        self.init(
            id: id,
            name: name,
            genericName: values["GenericName"],
            comment: values["Comment"],
            icon: values["Icon"],
            exec: values["Exec"],
            startupWMClass: values["StartupWMClass"],
            categories: values["Categories"]?.split(separator: ";").map(String.init) ?? [],
            noDisplay: values["NoDisplay"] == "true",
            hidden: values["Hidden"] == "true",
            terminal: values["Terminal"] == "true"
        )
    }

    /// Whether a window with this Wayland `app_id` belongs to the entry.
    func matches(appID: String) -> Bool {
        appID == id
            || appID == startupWMClass
            || appID.lowercased() == id.lowercased()
            || id.hasSuffix("." + appID)
    }

    /// The command to run, split into arguments with field codes removed.
    /// Files and URLs are not passed yet.
    var commandLine: [String]? {
        guard let exec else {
            return nil
        }
        let arguments = Self.splitArguments(exec).filter { argument in
            // %f %F %u %U %i %c %k and deprecated codes stand alone.
            !(argument.count == 2 && argument.hasPrefix("%"))
        }
        return arguments.isEmpty ? nil : arguments.map { $0.replacingOccurrences(of: "%%", with: "%") }
    }

    private static func unescape(_ value: String) -> String {
        var result = ""
        var iterator = value.makeIterator()
        while let character = iterator.next() {
            guard character == "\\", let next = iterator.next() else {
                result.append(character)
                continue
            }
            switch next {
            case "s": result.append(" ")
            case "n": result.append("\n")
            case "t": result.append("\t")
            case "r": result.append("\r")
            case "\\": result.append("\\")
            default:
                result.append(character)
                result.append(next)
            }
        }
        return result
    }

    /// Splits an Exec value on spaces, honoring double quotes.
    private static func splitArguments(_ exec: String) -> [String] {
        var arguments = [String]()
        var current = ""
        var quoted = false
        var escaped = false
        var hasArgument = false
        for character in exec {
            if escaped {
                current.append(character)
                escaped = false
            } else if quoted && character == "\\" {
                escaped = true
            } else if character == "\"" {
                quoted.toggle()
                hasArgument = true
            } else if character == " " && !quoted {
                if hasArgument || !current.isEmpty {
                    arguments.append(current)
                }
                current = ""
                hasArgument = false
            } else {
                current.append(character)
            }
        }
        if hasArgument || !current.isEmpty {
            arguments.append(current)
        }
        return arguments
    }
}

// MARK: - Search

public extension DesktopEntry {

    /// The `applications` folders to search, most important first:
    /// `$XDG_DATA_HOME` then each of `$XDG_DATA_DIRS`.
    static func applicationDirectories(environment: [String: String] = ProcessInfo.processInfo.environment) -> [URL] {
        let home = environment["HOME"] ?? NSHomeDirectory()
        let dataHome = environment["XDG_DATA_HOME"].flatMap { $0.isEmpty ? nil : $0 } ?? home + "/.local/share"
        let dataDirectories = environment["XDG_DATA_DIRS"].flatMap { $0.isEmpty ? nil : $0 } ?? "/usr/local/share:/usr/share"
        return ([dataHome] + dataDirectories.split(separator: ":").map(String.init))
            .map { URL(fileURLWithPath: $0).appendingPathComponent("applications", isDirectory: true) }
    }

    /// Every application entry in the given folders. Where two have the same
    /// ID, the one in the earlier folder wins, and hidden ones are dropped.
    static func installed(in directories: [URL] = applicationDirectories()) -> [DesktopEntry] {
        var entries = [String: DesktopEntry]()
        let fileManager = FileManager.default
        for directory in directories {
            // Paths relative to the folder, which make the ID.
            guard let enumerator = fileManager.enumerator(atPath: directory.path) else {
                continue
            }
            for case let relative as String in enumerator where relative.hasSuffix(".desktop") {
                let url = directory.appendingPathComponent(relative)
                let id = String(relative.dropLast(".desktop".count)).replacingOccurrences(of: "/", with: "-")
                guard entries[id] == nil,
                      let contents = try? String(contentsOf: url, encoding: .utf8),
                      let entry = DesktopEntry(id: id, contents: contents)
                else {
                    continue
                }
                entries[id] = entry
            }
        }
        return entries.values
            .filter { !$0.hidden }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}
