//
//  StatusNotifierHost.swift
//  CacaoShellKit
//

import DBus
#if canImport(Glibc)
import Glibc
#elseif canImport(Darwin)
import Darwin
#endif

/// A status item, as the menu bar shows it.
public struct StatusItem: Identifiable, Equatable, Sendable {

    /// Whether the item wants to be seen.
    public enum Status: String, Sendable {
        /// Hidden, as an idle item asks.
        case passive = "Passive"
        case active = "Active"
        /// Asking for the user's attention.
        case needsAttention = "NeedsAttention"
    }

    /// Its bus name and object path run together, as the watcher names it.
    public let id: String

    public let busName: DBusBusName

    public let path: DBusObjectPath

    /// The app's name for the item, such as `nm-applet`.
    public var itemID: String?

    public var title: String?

    /// An icon theme name.
    public var iconName: String?

    public var status: Status

    public var toolTip: String?

    /// Where the item's com.canonical.dbusmenu menu is, if it has one.
    public var menu: DBusObjectPath?

    /// Whether a click should show the menu instead of activating it.
    public var itemIsMenu: Bool

    /// What to show for the item until icons are drawn: its title, else
    /// its ID, else its bus name.
    public var displayName: String {
        [title, itemID].compactMap { $0 }.first { !$0.isEmpty } ?? busName.rawValue
    }
}

/// Reads status items from the StatusNotifierWatcher and follows their
/// changes, for the menu bar.
public actor StatusNotifierHost {

    public let connection: DBusConnection

    /// The items, in the order they registered.
    public private(set) var items = [StatusItem]()

    private var continuation: AsyncStream<[StatusItem]>.Continuation?

    private var tasks = [Task<Void, Never>]()

    /// The items being read, and whether they changed while being read,
    /// which reads them again once the read is done.
    private var loading = [String: Bool]()

    public init(connection: DBusConnection) {
        self.connection = connection
    }

    /// Registers as a host with the watcher and reads its items.
    ///
    /// - Returns: The items each time they change, starting with the items
    ///   registered now.
    public func start() async throws -> AsyncStream<[StatusItem]> {
        let watcherSignals = try await connection.signals(
            interface: ShellDBus.statusNotifierWatcherInterface,
            path: ShellDBus.statusNotifierWatcherPath
        )
        let itemSignals = try await connection.signals(interface: ShellDBus.statusNotifierItemInterface)

        let hostName = "org.kde.StatusNotifierHost-\(getpid())"
        if let name = DBusBusName(rawValue: hostName) {
            try await connection.requestName(name)
        }
        try await connection.callMethod(
            destination: ShellDBus.statusNotifierWatcherName,
            path: ShellDBus.statusNotifierWatcherPath,
            interface: ShellDBus.statusNotifierWatcherInterface,
            method: DBusMember(rawValue: "RegisterStatusNotifierHost")!,
            arguments: [.string(hostName)]
        )

        let (stream, continuation) = AsyncStream<[StatusItem]>.makeStream(bufferingPolicy: .bufferingNewest(1))
        self.continuation = continuation

        let registered = try await connection.getProperty(
            destination: ShellDBus.statusNotifierWatcherName,
            path: ShellDBus.statusNotifierWatcherPath,
            interface: ShellDBus.statusNotifierWatcherInterface,
            name: "RegisteredStatusNotifierItems"
        )
        if case let .array(names) = registered {
            for case let .string(name) in names {
                await load(name)
            }
        }
        continuation.yield(items)

        tasks.append(Task { [weak self] in
            for await message in watcherSignals {
                guard case let .string(name)? = message.arguments.first else { continue }
                switch message.member?.rawValue {
                case "StatusNotifierItemRegistered":
                    await self?.load(name)
                case "StatusNotifierItemUnregistered":
                    await self?.remove(name)
                default:
                    break
                }
            }
        })
        tasks.append(Task { [weak self] in
            // NewTitle, NewIcon, NewStatus and the rest: read the item again.
            for await message in itemSignals {
                guard let sender = message.sender, let path = message.path else { continue }
                await self?.reload(sender: sender, path: path)
            }
        })
        return stream
    }

    public func stop() {
        tasks.forEach { $0.cancel() }
        tasks = []
        continuation?.finish()
        continuation = nil
    }

    // MARK: Actions

    /// The item's primary action, as for a left click, at a point on the
    /// screen.
    public func activate(_ item: StatusItem, x: Int32 = 0, y: Int32 = 0) async throws {
        try await call(item, "Activate", [.int32(x), .int32(y)])
    }

    /// The item's secondary action, as for a middle click.
    public func secondaryActivate(_ item: StatusItem, x: Int32 = 0, y: Int32 = 0) async throws {
        try await call(item, "SecondaryActivate", [.int32(x), .int32(y)])
    }

    /// Asks the item to show its own context menu.
    public func contextMenu(_ item: StatusItem, x: Int32 = 0, y: Int32 = 0) async throws {
        try await call(item, "ContextMenu", [.int32(x), .int32(y)])
    }

    private func call(_ item: StatusItem, _ method: String, _ arguments: [DBusMessageArgument]) async throws {
        try await connection.callMethod(
            destination: item.busName,
            path: item.path,
            interface: ShellDBus.statusNotifierItemInterface,
            method: DBusMember(rawValue: method)!,
            arguments: arguments
        )
    }

    // MARK: Items

    private func load(_ name: String) async {
        // Already being read: read again once that's done, as it may have
        // been answered before this change.
        guard loading[name] == nil else {
            loading[name] = true
            return
        }
        guard let (busName, path) = StatusNotifierWatcher.split(name) else { return }
        repeat {
            loading[name] = false
            let properties = try? await connection.getAllProperties(
                destination: busName,
                path: path,
                interface: ShellDBus.statusNotifierItemInterface
            )
            // Unregistered while it was read: it stays gone.
            guard loading[name] != nil else { return }
            guard let properties else { break }
            let item = Self.item(id: name, busName: busName, path: path, properties: properties)
            if let index = items.firstIndex(where: { $0.id == name }) {
                if items[index] != item {
                    items[index] = item
                    continuation?.yield(items)
                }
            } else {
                items.append(item)
                continuation?.yield(items)
            }
        } while loading[name] == true
        loading[name] = nil
    }

    private func remove(_ name: String) {
        loading[name] = nil
        guard items.contains(where: { $0.id == name }) else { return }
        items.removeAll { $0.id == name }
        continuation?.yield(items)
    }

    private func reload(sender: DBusBusName, path: DBusObjectPath) async {
        // The signal comes from the item's unique name, which a well-known
        // name it registered with doesn't show, so those are read again too.
        func matches(_ busName: DBusBusName, _ itemPath: DBusObjectPath) -> Bool {
            itemPath == path && (busName == sender || !busName.rawValue.hasPrefix(":"))
        }
        let names = items.filter { matches($0.busName, $0.path) }.map(\.id)
            + loading.keys.filter { name in
                StatusNotifierWatcher.split(name).map { matches($0.busName, $0.path) } ?? false
            }
        for name in Set(names) {
            await load(name)
        }
    }

    /// An item from its `org.kde.StatusNotifierItem` properties.
    static func item(id: String, busName: DBusBusName, path: DBusObjectPath, properties: [String: DBusMessageArgument]) -> StatusItem {
        func string(_ key: String) -> String? {
            guard case let .string(value)? = properties[key] else { return nil }
            return value
        }
        var toolTip: String?
        // (sa(iiay)ss): icon name, icon pixmaps, title, description.
        if case let .struct(fields)? = properties["ToolTip"], fields.count == 4, case let .string(title) = fields[2], !title.isEmpty {
            toolTip = title
        }
        var menu: DBusObjectPath?
        if case let .objectPath(path)? = properties["Menu"], path.rawValue != "/" {
            menu = path
        }
        var itemIsMenu = false
        if case let .boolean(value)? = properties["ItemIsMenu"] {
            itemIsMenu = value
        }
        return StatusItem(
            id: id,
            busName: busName,
            path: path,
            itemID: string("Id"),
            title: string("Title"),
            iconName: string("IconName"),
            status: string("Status").flatMap(StatusItem.Status.init(rawValue:)) ?? .active,
            toolTip: toolTip,
            menu: menu,
            itemIsMenu: itemIsMenu
        )
    }
}
