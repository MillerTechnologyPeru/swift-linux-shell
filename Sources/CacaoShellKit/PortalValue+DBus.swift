//
//  PortalValue+DBus.swift
//  CacaoShellKit
//

import DBus

public extension PortalValue {

    /// The value as a D-Bus message argument, not wrapped in a variant.
    var messageArgument: DBusMessageArgument {
        switch self {
        case let .uint32(value):
            return .uint32(value)
        case let .int32(value):
            return .int32(value)
        case let .string(value):
            return .string(value)
        case let .bool(value):
            return .boolean(value)
        case let .color(red, green, blue):
            // Three doubles always make a valid structure.
            return .struct(DBusMessageArgument.Structure([.double(red), .double(green), .double(blue)])!)
        }
    }

    /// The value wrapped in a variant, as `Read` and `SettingChanged` send it.
    var variant: DBusMessageArgument {
        .variant(DBusMessageArgument.Variant(messageArgument))
    }
}

public extension AppearanceSettings {

    /// Namespaces to keys to values, as `ReadAll` returns them: `a{sa{sv}}`.
    static func readAllArgument(_ values: [String: [String: PortalValue]]) throws -> DBusMessageArgument {
        guard let innerType = DBusSignature.DictionaryType(key: .string, value: .variant) else {
            throw DBusProtocolError.invalidValue("Could not make the a{sv} type")
        }
        var namespaces = [DBusMessageArgument.Dictionary.Entry]()
        for (namespace, keys) in values.sorted(by: { $0.key < $1.key }) {
            let entries = keys.sorted(by: { $0.key < $1.key }).map { key, value in
                DBusMessageArgument.Dictionary.Entry(key: .string(key), value: value.variant)
            }
            guard let inner = DBusMessageArgument.Dictionary(keyType: .string, valueType: .variant, entries) else {
                throw DBusProtocolError.invalidValue("Could not build the settings of \(namespace)")
            }
            namespaces.append(DBusMessageArgument.Dictionary.Entry(key: .string(namespace), value: .dictionary(inner)))
        }
        guard let outer = DBusMessageArgument.Dictionary(keyType: .string, valueType: .dictionary(innerType), namespaces) else {
            throw DBusProtocolError.invalidValue("Could not build the settings dictionary")
        }
        return .dictionary(outer)
    }
}
