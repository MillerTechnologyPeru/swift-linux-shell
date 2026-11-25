//
//  NotificationBanners.swift
//  CacaoMenuBar
//
//  Apps' notifications, shown as banners at the top right of the screen,
//  below the menu bar. The menu bar runs the desktop's notification server.
//

import CacaoSDL
import CacaoShellKit
import DBus
import Foundation

/// The notifications to show: one banner at a time, the rest waiting in
/// the order they came.
@MainActor
final class Notifications: ObservableObject {

    static let shared = Notifications()

    static let bannerWindowID = "notification-banner"

    /// How long a banner shows when its app leaves it to the server.
    static let defaultDuration: Duration = .seconds(5)

    /// The banner showing.
    @Published private(set) var current: DesktopNotification?

    /// Opens and closes the banner's window, from views that have them.
    var openWindow: OpenWindowAction?
    var dismissWindow: DismissWindowAction?

    private var waiting: [DesktopNotification] = []

    private var server: NotificationServer?

    private var expiry: Task<Void, Never>?

    private init() { }

    /// Serves `org.freedesktop.Notifications`, unless another process does.
    func start() async {
        guard server == nil else { return }
        do {
            let connection = try await DBusConnection.connect(to: .session)
            let server = NotificationServer(connection: connection)
            guard try await server.start() else {
                print("[CacaoMenuBar] Another process shows notifications")
                await connection.close()
                return
            }
            self.server = server
            Task { [weak self] in
                for await event in server.events {
                    self?.handle(event)
                }
            }
        } catch {
            print("[CacaoMenuBar] Notifications aren't available: \(error)")
        }
    }

    // MARK: From the banner

    /// Clicking the banner: its default action, or closing it.
    func click() {
        guard let current else { return }
        if current.hasDefaultAction {
            invoke("default")
        } else {
            dismiss()
        }
    }

    /// One of the banner's buttons.
    func invoke(_ key: String) {
        guard let current, let server else { return }
        let id = current.id
        Task { await server.invoke(id, action: key) }
    }

    /// The banner's close button.
    func dismiss() {
        guard let current, let server else { return }
        let id = current.id
        Task { await server.close(id, reason: .dismissed) }
    }

    // MARK: From the server

    private func handle(_ event: NotificationServer.Event) {
        switch event {
        case let .posted(notification):
            if current?.id == notification.id {
                // Replaced in place: the new text, and the time starts over.
                current = notification
                scheduleExpiry(for: notification)
            } else if let index = waiting.firstIndex(where: { $0.id == notification.id }) {
                waiting[index] = notification
            } else {
                waiting.append(notification)
            }
        case let .closed(id):
            if current?.id == id {
                current = nil
                expiry?.cancel()
            } else {
                waiting.removeAll { $0.id == id }
            }
        }
        showNext()
    }

    private func showNext() {
        if current == nil, !waiting.isEmpty {
            let next = waiting.removeFirst()
            current = next
            scheduleExpiry(for: next)
        }
        if current != nil {
            openWindow?(id: Self.bannerWindowID)
        } else {
            dismissWindow?(id: Self.bannerWindowID)
        }
    }

    private func scheduleExpiry(for notification: DesktopNotification) {
        expiry?.cancel()
        let duration: Duration?
        switch notification.expireTimeout {
        case 0:
            duration = nil
        case ..<0:
            // Critical ones wait to be closed, as the specification asks.
            duration = notification.urgency == .critical ? nil : Self.defaultDuration
        default:
            duration = .milliseconds(Int(notification.expireTimeout))
        }
        guard let duration, let server else { return }
        let id = notification.id
        expiry = Task {
            try? await Task.sleep(for: duration)
            guard !Task.isCancelled else { return }
            await server.close(id, reason: .expired)
        }
    }
}

/// A notification's banner: the app's name, the summary and the body, with
/// its buttons. Clicking it does the default action.
struct NotificationBanner: View {

    @ObservedObject var notifications = Notifications.shared

    var body: some View {
        if let notification = notifications.current {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: "bell")
                        .foregroundStyle(.secondary)
                    Text(notification.appName.isEmpty ? "Notification" : notification.appName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer()
                    Button {
                        notifications.dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                }
                Text(notification.summary)
                    .font(.headline)
                    .lineLimit(1)
                if !notification.body.isEmpty {
                    Text(notification.body)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                if !notification.buttons.isEmpty {
                    HStack {
                        Spacer()
                        ForEach(notification.buttons, id: \.key) { action in
                            Button(action.label) {
                                notifications.invoke(action.key)
                            }
                        }
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .contentShape(Rectangle())
            .onTapGesture {
                notifications.click()
            }
        }
    }
}
