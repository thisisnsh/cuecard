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
            NotificationIcon(severity: notification.severity, size: 30)

            VStack(alignment: .leading, spacing: 3) {
                Text(notification.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppColors.textPrimary(for: colorScheme))
                    .fixedSize(horizontal: false, vertical: true)

                if let body = notification.body {
                    Text(body)
                        .font(.footnote)
                        .foregroundStyle(AppColors.textSecondary(for: colorScheme))
                        .fixedSize(horizontal: false, vertical: true)
                }

                if !notification.actions.isEmpty {
                    HStack(spacing: 8) {
                        ForEach(Array(notification.actions.enumerated()), id: \.offset) { index, action in
                            Button(action.label) {
                                perform(action)
                            }
                            .buttonStyle(NotificationActionStyle(tint: accentColor, isPrimary: index == 0))
                        }
                    }
                    .padding(.top, 8)
                }
            }
            .padding(.top, notification.body == nil ? 5 : 0)

            Spacer(minLength: 0)

            if notification.dismissible {
                NotificationCloseButton(action: dismiss)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassedEffect(in: RoundedRectangle(cornerRadius: 20, style: .continuous))
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
            NotificationIcon(severity: notification.severity, size: 28)

            VStack(alignment: .leading, spacing: 3) {
                Text(notification.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppColors.textPrimary(for: colorScheme))
                    .fixedSize(horizontal: false, vertical: true)

                if let body = notification.body {
                    Text(body)
                        .font(.footnote)
                        .foregroundStyle(AppColors.textSecondary(for: colorScheme))
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let action = primaryAction {
                    Button(action.label) {
                        perform(action)
                    }
                    .buttonStyle(NotificationActionStyle(
                        tint: NotificationStyle.accent(for: notification.severity, colorScheme: colorScheme),
                        isPrimary: true
                    ))
                    .padding(.top, 8)
                }
            }
            .padding(.top, notification.body == nil ? 4 : 0)

            Spacer(minLength: 0)

            if notification.dismissible {
                NotificationCloseButton {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        notifications.dismiss(notification)
                    }
                }
            }
        }
        .padding(.vertical, 6)
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

/// The severity, as a symbol on a soft tint of its colour.
private struct NotificationIcon: View {
    let severity: RemoteNotification.Severity
    let size: CGFloat

    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        let accent = NotificationStyle.accent(for: severity, colorScheme: colorScheme)

        Image(systemName: NotificationStyle.symbol(for: severity))
            .font(.system(size: size * 0.5, weight: .semibold))
            .foregroundStyle(accent)
            .frame(width: size, height: size)
            .background(accent.opacity(0.16), in: Circle())
            .accessibilityHidden(true)
    }
}

private struct NotificationCloseButton: View {
    let action: () -> Void

    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(AppColors.textSecondary(for: colorScheme))
                .frame(width: 24, height: 24)
                .background(AppColors.textSecondary(for: colorScheme).opacity(0.14), in: Circle())
                .contentShape(Circle())
        }
        // Borderless, so in a List row the X doesn't also fire the row's other button.
        .buttonStyle(.borderless)
        .accessibilityLabel("Dismiss")
    }
}

/// A small capsule: filled with a tint of the severity colour for the first
/// action, bare text for the second.
private struct NotificationActionStyle: ButtonStyle {
    let tint: Color
    let isPrimary: Bool

    @Environment(\.colorScheme) var colorScheme

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.footnote.weight(.semibold))
            .foregroundStyle(isPrimary ? tint : AppColors.textSecondary(for: colorScheme))
            .padding(.horizontal, isPrimary ? 12 : 4)
            .padding(.vertical, 6)
            .background {
                if isPrimary {
                    Capsule().fill(tint.opacity(0.16))
                }
            }
            .contentShape(Capsule())
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}

enum NotificationStyle {
    static func symbol(for severity: RemoteNotification.Severity) -> String {
        switch severity {
        case .info:
            return "info"
        case .warning:
            return "exclamationmark"
        case .critical:
            return "exclamationmark.2"
        }
    }

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
