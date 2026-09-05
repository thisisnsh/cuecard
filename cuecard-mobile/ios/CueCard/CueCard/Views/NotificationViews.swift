import SwiftUI
import FirebaseAnalytics

/// A notice from the worker, shown as a card above the editor.
struct NotificationBanner: View {
    let notification: RemoteNotification

    @EnvironmentObject var notifications: RemoteNotificationService
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.openURL) private var openURL

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(notification.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppColors.textPrimary(for: colorScheme))

                if let body = notification.body {
                    Text(body)
                        .font(.caption)
                        .foregroundStyle(AppColors.textSecondary(for: colorScheme))
                        .fixedSize(horizontal: false, vertical: true)
                }

                if !notification.actions.isEmpty {
                    HStack(spacing: 20) {
                        ForEach(Array(notification.actions.enumerated()), id: \.offset) { _, action in
                            Button(action.label) {
                                perform(action)
                            }
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(accentColor)
                        }
                    }
                    .padding(.top, 2)
                }
            }

            Spacer(minLength: 0)

            if notification.dismissible {
                Button(action: dismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(AppColors.textSecondary(for: colorScheme))
                        .padding(6)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss")
            }
        }
        .padding(12)
        .padding(.leading, 10)
        .glassedEffect(in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        // The severity stripe goes in an overlay rather than the stack: a Shape is
        // greedy in its unconstrained axis, and inline it stretches the whole card
        // down the screen next to the editor.
        .overlay(alignment: .leading) {
            Capsule()
                .fill(accentColor)
                .frame(width: 3)
                .padding(.vertical, 10)
                .padding(.leading, 10)
        }
        .onAppear {
            notifications.logImpression(notification)
        }
    }

    private var accentColor: Color {
        NotificationStyle.accent(for: notification.severity, colorScheme: colorScheme)
    }

    private func dismiss() {
        withAnimation(.easeInOut(duration: 0.2)) {
            notifications.dismiss(notification)
        }
    }

    private func perform(_ action: RemoteNotification.Action) {
        notifications.logAction(action, in: notification)

        switch action.kind {
        case .openURL:
            if let url = action.url {
                openURL(url)
            }
        case .appStore:
            openURL(AppLinks.appStore)
        case .dismiss:
            dismiss()
        }
    }
}

/// The same notice in a quieter place: a row at the top of Settings. Used for
/// anything not worth interrupting someone's script for.
struct NotificationRow: View {
    let notification: RemoteNotification

    @EnvironmentObject var notifications: RemoteNotificationService
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.openURL) private var openURL

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(notification.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppColors.textPrimary(for: colorScheme))

                if let body = notification.body {
                    Text(body)
                        .font(.caption)
                        .foregroundStyle(AppColors.textSecondary(for: colorScheme))
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let action = primaryAction {
                    Button(action.label) {
                        perform(action)
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(NotificationStyle.accent(for: notification.severity, colorScheme: colorScheme))
                    .padding(.top, 2)
                }
            }

            Spacer(minLength: 0)

            if notification.dismissible {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        notifications.dismiss(notification)
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(AppColors.textSecondary(for: colorScheme))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss")
            }
        }
        .padding(.vertical, 4)
        .onAppear {
            notifications.logImpression(notification)
        }
    }

    /// A settings row has space for one thing to do; dismissal already has its own
    /// control, so the X is the action we skip here.
    private var primaryAction: RemoteNotification.Action? {
        notification.actions.first { $0.kind != .dismiss }
    }

    private func perform(_ action: RemoteNotification.Action) {
        notifications.logAction(action, in: notification)

        switch action.kind {
        case .openURL:
            if let url = action.url {
                openURL(url)
            }
        case .appStore:
            openURL(AppLinks.appStore)
        case .dismiss:
            notifications.dismiss(notification)
        }
    }
}

enum NotificationStyle {
    static func accent(for severity: RemoteNotification.Severity, colorScheme: ColorScheme) -> Color {
        switch severity {
        case .info:
            return AppColors.blue(for: colorScheme)
        case .warning:
            return AppColors.yellow(for: colorScheme)
        case .critical:
            return AppColors.red(for: colorScheme)
        }
    }
}
