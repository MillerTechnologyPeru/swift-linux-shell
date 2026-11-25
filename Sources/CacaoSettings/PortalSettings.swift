//
//  PortalSettings.swift
//  CacaoSettings
//

import CacaoShellKit
import DBus

/// The settings service's D-Bus objects: the portal backend that apps read
/// through xdg-desktop-portal, and the shell's own interface for changing
/// values.
struct PortalSettings {

    let store: SettingsStore

    /// Emitted for each key that changes, with its new value.
    static let settingChanged = DBusMessage.Signal(
        path: ShellDBus.portalPath,
        interface: ShellDBus.portalSettingsBackendInterface,
        name: DBusMember(rawValue: "SettingChanged")!
    )

    /// Serves both objects on a connection. Changes made through the shell's
    /// interface are emitted as `SettingChanged`.
    func export(on connection: DBusConnection) async {
        await connection.export(DBusExportedObject([portalBackend()]), at: ShellDBus.portalPath)
        let shell = shellInterface { changes in
            for change in changes {
                log("\(change.namespace) \(change.key) changed")
                do {
                    try await connection.emit(Self.settingChanged, arguments: [
                        .string(change.namespace),
                        .string(change.key),
                        change.value.variant,
                    ])
                } catch {
                    log("Could not emit SettingChanged: \(error)")
                }
            }
        }
        await connection.export(DBusExportedObject([shell]), at: ShellDBus.settingsPath)
    }

    /// `org.freedesktop.impl.portal.Settings`, version 2.
    func portalBackend() -> DBusInterfaceImplementation {
        let store = self.store
        return DBusInterfaceImplementation(
            name: ShellDBus.portalSettingsBackendInterface,
            methods: [
                .init(
                    name: DBusMember(rawValue: "ReadAll")!,
                    inputSignature: DBusSignature(rawValue: "as")!,
                    outputSignature: DBusSignature(rawValue: "a{sa{sv}}")!,
                    inputNames: ["namespaces"],
                    outputNames: ["value"]
                ) { call in
                    let patterns: [String]
                    if case let .array(array)? = call.arguments.first {
                        patterns = array.compactMap(\.stringValue)
                    } else {
                        patterns = []
                    }
                    let values = await store.settings.portalValues(matching: patterns)
                    return [try AppearanceSettings.readAllArgument(values)]
                },
                .init(
                    name: DBusMember(rawValue: "Read")!,
                    inputSignature: DBusSignature(rawValue: "ss")!,
                    outputSignature: DBusSignature(rawValue: "v")!,
                    inputNames: ["namespace", "key"],
                    outputNames: ["value"]
                ) { call in
                    let (namespace, key) = try Self.namespaceAndKey(call)
                    guard let value = await store.settings.portalValue(namespace: namespace, key: key) else {
                        throw Self.notFound(namespace, key)
                    }
                    return [value.variant]
                },
            ],
            properties: [
                .init(name: "version", type: .uint32) { .uint32(2) }
            ],
            signals: [
                .init(
                    name: DBusMember(rawValue: "SettingChanged")!,
                    signature: DBusSignature(rawValue: "ssv")!,
                    argumentNames: ["namespace", "key", "value"]
                )
            ]
        )
    }

    /// The shell's interface: `Set(s namespace, s key, v value)` with the
    /// same keys the portal serves. The settings app and the menu bar's
    /// appearance toggle use it.
    func shellInterface(onChange: @escaping @Sendable ([(namespace: String, key: String, value: PortalValue)]) async -> Void) -> DBusInterfaceImplementation {
        let store = self.store
        return DBusInterfaceImplementation(
            name: ShellDBus.settingsInterface,
            methods: [
                .init(
                    name: DBusMember(rawValue: "Set")!,
                    inputSignature: DBusSignature(rawValue: "ssv")!,
                    inputNames: ["namespace", "key", "value"]
                ) { call in
                    let (namespace, key) = try Self.namespaceAndKey(call)
                    guard call.arguments.count == 3, let value = call.arguments[2].variantValue else {
                        throw DBusError(name: .invalidArguments, message: "Set takes a namespace, a key and a variant")
                    }
                    let changes = try await store.update { settings in
                        Self.apply(value, namespace: namespace, key: key, to: &settings)
                    }
                    await onChange(changes)
                    return []
                }
            ]
        )
    }

    private static func namespaceAndKey(_ call: DBusMethodCall) throws -> (String, String) {
        guard call.arguments.count >= 2,
              case let .string(namespace) = call.arguments[0],
              case let .string(key) = call.arguments[1]
        else {
            throw DBusError(name: .invalidArguments, message: "Expected a namespace and a key")
        }
        return (namespace, key)
    }

    private static func notFound(_ namespace: String, _ key: String) -> DBusError {
        DBusError(
            name: DBusError.Name(rawValue: "org.freedesktop.portal.Error.NotFound")!,
            message: "Requested setting \(namespace) \(key) not found"
        )
    }

    /// Changes the setting a key names. Keys the service doesn't hold, and
    /// values of the wrong type, are ignored.
    private static func apply(_ value: DBusMessageArgument, namespace: String, key: String, to settings: inout AppearanceSettings) {
        switch (namespace, key, value) {
        case ("org.freedesktop.appearance", "color-scheme", let .uint32(raw)):
            if let scheme = AppearanceSettings.ColorScheme(rawValue: raw) {
                settings.colorScheme = scheme
            }
        case ("org.freedesktop.appearance", "contrast", let .uint32(raw)):
            if let contrast = AppearanceSettings.Contrast(rawValue: raw) {
                settings.contrast = contrast
            }
        case ("org.freedesktop.appearance", "accent-color", let .struct(structure)):
            let components = structure.compactMap { argument -> Double? in
                if case let .double(component) = argument { return component }
                return nil
            }
            if components.count == 3 {
                settings.accentColor = .init(red: components[0], green: components[1], blue: components[2])
            }
        case ("org.gnome.desktop.interface", "font-name", let .string(name)):
            settings.fontName = name
        case ("org.gnome.desktop.interface", "monospace-font-name", let .string(name)):
            settings.monospaceFontName = name
        case ("org.gnome.desktop.interface", "icon-theme", let .string(name)):
            settings.iconTheme = name
        case ("org.gnome.desktop.interface", "cursor-theme", let .string(name)):
            settings.cursorTheme = name
        case ("org.gnome.desktop.interface", "cursor-size", let .int32(size)):
            settings.cursorSize = size
        case ("org.gnome.desktop.wm.preferences", "button-layout", let .string(layout)):
            settings.buttonLayout = layout
        case (AppearanceSettings.cacaoNamespace, "effects", let .boolean(on)),
             ("org.gnome.desktop.interface", "enable-animations", let .boolean(on)):
            settings.effects = on
        default:
            break
        }
    }
}
