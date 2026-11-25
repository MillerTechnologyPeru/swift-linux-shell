//
//  AppearanceSettings.swift
//  CacaoShellKit
//

/// The appearance state the settings service holds and serves through the
/// portal: one source of truth for Cacao apps, Perry's Mac apps and Flatpak
/// GNOME apps.
public struct AppearanceSettings: Codable, Equatable, Hashable, Sendable {

    public var colorScheme: ColorScheme

    public var accentColor: AccentColor

    public var contrast: Contrast

    /// Window buttons, in GNOME's `button-layout` syntax. The close,
    /// minimize and maximize buttons are on the left by default.
    public var buttonLayout: String

    public var fontName: String

    public var monospaceFontName: String

    public var iconTheme: String

    public var cursorTheme: String

    public var cursorSize: Int32

    /// The form factor of each screen, by output name. Screens not listed
    /// use the device's default.
    public var formFactors: [String: FormFactor]

    /// Whether the desktop draws its effects: window shadows and
    /// animations. Off by default on PowerPC, whose GPUs are too slow.
    public var effects: Bool

    /// Effects' default for this machine.
    public static var defaultEffects: Bool {
        #if arch(powerpc) || arch(powerpc64)
        false
        #else
        true
        #endif
    }

    public init(
        colorScheme: ColorScheme = .noPreference,
        accentColor: AccentColor = .blue,
        contrast: Contrast = .normal,
        buttonLayout: String = "close,minimize,maximize:",
        fontName: String = "Inter 10",
        monospaceFontName: String = "JetBrains Mono 10",
        iconTheme: String = "elementary",
        cursorTheme: String = "Adwaita",
        cursorSize: Int32 = 24,
        formFactors: [String: FormFactor] = [:],
        effects: Bool = AppearanceSettings.defaultEffects
    ) {
        self.colorScheme = colorScheme
        self.accentColor = accentColor
        self.contrast = contrast
        self.buttonLayout = buttonLayout
        self.fontName = fontName
        self.monospaceFontName = monospaceFontName
        self.iconTheme = iconTheme
        self.cursorTheme = cursorTheme
        self.cursorSize = cursorSize
        self.formFactors = formFactors
        self.effects = effects
    }

    /// Reads saved settings. A key the file doesn't have, as when it was
    /// saved before the key existed, takes its default.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = AppearanceSettings()
        colorScheme = try container.decodeIfPresent(ColorScheme.self, forKey: .colorScheme) ?? defaults.colorScheme
        accentColor = try container.decodeIfPresent(AccentColor.self, forKey: .accentColor) ?? defaults.accentColor
        contrast = try container.decodeIfPresent(Contrast.self, forKey: .contrast) ?? defaults.contrast
        buttonLayout = try container.decodeIfPresent(String.self, forKey: .buttonLayout) ?? defaults.buttonLayout
        fontName = try container.decodeIfPresent(String.self, forKey: .fontName) ?? defaults.fontName
        monospaceFontName = try container.decodeIfPresent(String.self, forKey: .monospaceFontName) ?? defaults.monospaceFontName
        iconTheme = try container.decodeIfPresent(String.self, forKey: .iconTheme) ?? defaults.iconTheme
        cursorTheme = try container.decodeIfPresent(String.self, forKey: .cursorTheme) ?? defaults.cursorTheme
        cursorSize = try container.decodeIfPresent(Int32.self, forKey: .cursorSize) ?? defaults.cursorSize
        formFactors = try container.decodeIfPresent([String: FormFactor].self, forKey: .formFactors) ?? defaults.formFactors
        effects = try container.decodeIfPresent(Bool.self, forKey: .effects) ?? defaults.effects
    }
}

public extension AppearanceSettings {

    /// The portal's `color-scheme` values.
    enum ColorScheme: UInt32, Codable, CaseIterable, Sendable {
        case noPreference = 0
        case dark = 1
        case light = 2
    }

    /// The portal's `contrast` values.
    enum Contrast: UInt32, Codable, CaseIterable, Sendable {
        case normal = 0
        case high = 1
    }

    /// The portal's `accent-color`: sRGB components from 0 to 1.
    struct AccentColor: Codable, Equatable, Hashable, Sendable {

        public var red: Double
        public var green: Double
        public var blue: Double

        public init(red: Double, green: Double, blue: Double) {
            self.red = red
            self.green = green
            self.blue = blue
        }

        public static let blue = AccentColor(red: 0.21, green: 0.52, blue: 0.89)
    }
}

// MARK: - Portal keys

public extension AppearanceSettings {

    /// The namespace of the desktop's own settings in the portal.
    static let cacaoNamespace = "org.pureswift.cacao"

    /// The namespaces and keys the portal serves, each with its value.
    ///
    /// `org.freedesktop.appearance` is the standard namespace. The
    /// `org.gnome.*` ones answer the reads GTK makes through the portal in a
    /// Flatpak, so no GSettings store is needed.
    var portalValues: [String: [String: PortalValue]] {
        [
            "org.freedesktop.appearance": [
                "color-scheme": .uint32(colorScheme.rawValue),
                "accent-color": .color(accentColor.red, accentColor.green, accentColor.blue),
                "contrast": .uint32(contrast.rawValue),
            ],
            "org.gnome.desktop.interface": [
                "color-scheme": .string(gnomeColorScheme),
                "font-name": .string(fontName),
                "monospace-font-name": .string(monospaceFontName),
                "icon-theme": .string(iconTheme),
                "cursor-theme": .string(cursorTheme),
                "cursor-size": .int32(cursorSize),
                // GTK's animations follow the desktop's effects.
                "enable-animations": .bool(effects),
            ],
            "org.gnome.desktop.wm.preferences": [
                "button-layout": .string(buttonLayout),
            ],
            // The desktop's own: effects, which the window server follows.
            Self.cacaoNamespace: [
                "effects": .bool(effects),
            ],
        ]
    }

    /// GNOME's own name for the color scheme.
    private var gnomeColorScheme: String {
        switch colorScheme {
        case .noPreference: return "default"
        case .dark: return "prefer-dark"
        case .light: return "prefer-light"
        }
    }

    /// The value for one key, or nil if the portal doesn't serve it.
    func portalValue(namespace: String, key: String) -> PortalValue? {
        portalValues[namespace]?[key]
    }

    /// The namespaces matching a ReadAll pattern list. An empty list, or an
    /// empty pattern, matches everything; a trailing `*` matches a prefix.
    func portalValues(matching patterns: [String]) -> [String: [String: PortalValue]] {
        let all = portalValues
        let patterns = patterns.filter { !$0.isEmpty }
        guard !patterns.isEmpty else {
            return all
        }
        return all.filter { namespace, _ in
            patterns.contains { pattern in
                if pattern.hasSuffix("*") {
                    return namespace.hasPrefix(pattern.dropLast())
                }
                return namespace == pattern
            }
        }
    }

    /// The keys whose values differ from another settings value, as
    /// `(namespace, key, new value)`, for `SettingChanged`.
    func changes(from old: AppearanceSettings) -> [(namespace: String, key: String, value: PortalValue)] {
        let oldValues = old.portalValues
        var changes = [(namespace: String, key: String, value: PortalValue)]()
        for (namespace, values) in portalValues.sorted(by: { $0.key < $1.key }) {
            for (key, value) in values.sorted(by: { $0.key < $1.key }) where oldValues[namespace]?[key] != value {
                changes.append((namespace, key, value))
            }
        }
        return changes
    }
}

/// A setting's value as the portal sends it.
public enum PortalValue: Equatable, Hashable, Sendable {
    case uint32(UInt32)
    case int32(Int32)
    case string(String)
    case bool(Bool)
    /// An accent color: `(ddd)`.
    case color(Double, Double, Double)
}
