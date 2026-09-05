import SwiftUI
import FirebaseAnalytics

/// A notice from the worker, shown as a card above the editor.
struct RemoteMessageBanner: View {
    let message: RemoteMessage

    @EnvironmentObject var remoteConfig: RemoteConfigService
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.openURL) private var openURL

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(message.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppColors.textPrimary(for: colorScheme))

                if let body = message.body {
                    Text(body)
                        .font(.caption)
                        .foregroundStyle(AppColors.textSecondary(for: colorScheme))
                        .fixedSize(horizontal: false, vertical: true)
                }

                if !message.actions.isEmpty {
                    HStack(spacing: 20) {
                        ForEach(Array(message.actions.enumerated()), id: \.offset) { _, action in
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

            if message.dismissible {
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
            remoteConfig.logImpression(message)
        }
    }

    private var accentColor: Color {
        RemoteMessageStyle.accent(for: message.severity, colorScheme: colorScheme)
    }

    private func dismiss() {
        withAnimation(.easeInOut(duration: 0.2)) {
            remoteConfig.dismiss(message)
        }
    }

    private func perform(_ action: RemoteMessage.Action) {
        remoteConfig.logAction(action, in: message)

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
struct RemoteMessageRow: View {
    let message: RemoteMessage

    @EnvironmentObject var remoteConfig: RemoteConfigService
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.openURL) private var openURL

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(message.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppColors.textPrimary(for: colorScheme))

                if let body = message.body {
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
                    .foregroundStyle(RemoteMessageStyle.accent(for: message.severity, colorScheme: colorScheme))
                    .padding(.top, 2)
                }
            }

            Spacer(minLength: 0)

            if message.dismissible {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        remoteConfig.dismiss(message)
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
            remoteConfig.logImpression(message)
        }
    }

    /// A settings row has space for one thing to do; dismissal already has its own
    /// control, so the X is the action we skip here.
    private var primaryAction: RemoteMessage.Action? {
        message.actions.first { $0.kind != .dismiss }
    }

    private func perform(_ action: RemoteMessage.Action) {
        remoteConfig.logAction(action, in: message)

        switch action.kind {
        case .openURL:
            if let url = action.url {
                openURL(url)
            }
        case .appStore:
            openURL(AppLinks.appStore)
        case .dismiss:
            remoteConfig.dismiss(message)
        }
    }
}

/// Shown instead of the app when the worker says this build is below the floor.
/// There is deliberately no way past it — it exists for the case where a shipped
/// build is doing real damage and every other lever is a release away.
struct UpdateRequiredView: View {
    @EnvironmentObject var remoteConfig: RemoteConfigService
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.openURL) private var openURL

    var body: some View {
        ZStack {
            AppColors.background(for: colorScheme)
                .ignoresSafeArea()

            VStack(spacing: 24) {
                Image("Icon")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 72, height: 72)
                    .clipShape(RoundedRectangle(cornerRadius: 16))

                VStack(spacing: 10) {
                    Text("Update CueCard")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(AppColors.textPrimary(for: colorScheme))

                    Text("This version can't run anymore. Grab the latest one from the App Store — your notes are safe on this device.")
                        .font(.subheadline)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(AppColors.textSecondary(for: colorScheme))
                }

                Button {
                    AnalyticsEvents.logButtonClick("update_app", screen: "update_required")
                    openURL(remoteConfig.updateURL)
                } label: {
                    Text("Open App Store")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(colorScheme == .dark ? .black : .white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(AppColors.green(for: colorScheme))
                        )
                }
            }
            .padding(.horizontal, 32)
        }
        .onAppear {
            Analytics.logEvent(AnalyticsEventScreenView, parameters: [
                AnalyticsParameterScreenName: "update_required"
            ])
        }
    }
}

enum RemoteMessageStyle {
    static func accent(for severity: RemoteMessage.Severity, colorScheme: ColorScheme) -> Color {
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
