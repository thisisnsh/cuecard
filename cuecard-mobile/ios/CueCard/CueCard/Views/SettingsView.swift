import SwiftUI
import FirebaseAnalytics
import FirebaseAuth
import FirebaseCrashlytics

struct SettingsView: View {
    @EnvironmentObject var authService: AuthenticationService
    @EnvironmentObject var settingsService: SettingsService
    @EnvironmentObject var notifications: RemoteNotificationService
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme

    @State private var showingDeleteConfirmation = false
    @State private var isDeletingAccount = false
    @State private var deleteErrorMessage: String?

    /// The delay and the speed are typed rather than dragged, so each field
    /// holds text while it is being edited and only becomes a setting once
    /// editing stops.
    private enum NumberField { case delay, speed }

    @State private var countdownSecondsText = ""
    @State private var linesPerMinuteText = ""
    @FocusState private var focusedField: NumberField?

    private var isCrashlyticsTestEnabled: Bool {
        ProcessInfo.processInfo.environment["CRASHLYTICS_TEST_CRASH"] == "1"
    }

    var body: some View {
        NavigationStack {
            settingsList
                .navigationTitle("Settings")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") {
                            AnalyticsEvents.logButtonClick("done", screen: "settings")
                            dismiss()
                        }
                    }
                }
                .alert("Delete Account", isPresented: $showingDeleteConfirmation) {
                    Button("Cancel", role: .cancel) { }
                    Button("Delete", role: .destructive) {
                        deleteAccount()
                    }
                } message: {
                    Text("Are you sure you want to delete your account? This action cannot be undone.")
                }
                .alert("Error", isPresented: Binding(
                    get: { deleteErrorMessage != nil },
                    set: { if !$0 { deleteErrorMessage = nil } }
                )) {
                    Button("OK", role: .cancel) { }
                } message: {
                    Text(deleteErrorMessage ?? "An error occurred")
                }
        }
        .onAppear {
            countdownSecondsText = String(settingsService.settings.countdownSeconds)
            linesPerMinuteText = String(settingsService.settings.linesPerMinute)
            Analytics.logEvent(AnalyticsEventScreenView, parameters: [
                AnalyticsParameterScreenName: "settings"
            ])
        }
        .onChange(of: focusedField) { field in
            if field != .delay { commitCountdownSeconds() }
            if field != .speed { commitLinesPerMinute() }
        }
        .onChange(of: settingsService.settings.countdownSeconds) { seconds in
            if focusedField != .delay { countdownSecondsText = String(seconds) }
        }
        .onChange(of: settingsService.settings.linesPerMinute) { lines in
            if focusedField != .speed { linesPerMinuteText = String(lines) }
        }
    }

    private var settingsList: some View {
        List {
            remoteMessageSection
            userInfoSection
            rateSection
            teleprompterSection
            inAppPrompterSection
            floatingPrompterSection
            appearanceSection
            resetSection
            diagnosticsSection
            signOutSection
            deleteAccountSection
        }
        // The number pad has no return key, so the way out is to leave the
        // field: a scroll, or a tap anywhere that isn't a control of its own.
        // A low-priority gesture, so rows and boxes still get their own taps.
        .scrollDismissesKeyboard(.immediately)
        .gesture(TapGesture().onEnded { focusedField = nil })
    }

    /// A notice from the worker, if there's one meant for Settings. Quieter than
    /// the home banner — cross-promotion, deprecation notices, that sort of thing.
    @ViewBuilder
    private var remoteMessageSection: some View {
        if let notification = notifications.notification(for: .settingsRow) {
            Section {
                NotificationRow(notification: notification)
            }
        }
    }

    @ViewBuilder
    private var userInfoSection: some View {
        if let user = authService.user {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text(displayNameForUser(user))
                        .font(.headline)

                    if let email = user.email {
                        Text(email)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 8)
            }
        }
    }

    /// Take what was typed as a countdown, holding it to the range a run can
    /// wait for. Anything that isn't a number leaves the setting alone.
    private func commitCountdownSeconds() {
        let digits = countdownSecondsText.filter(\.isNumber)
        if let typed = Int(digits) {
            let clamped = min(max(typed, TeleprompterSettings.countdownRange.lowerBound), TeleprompterSettings.countdownRange.upperBound)
            settingsService.settings.countdownSeconds = clamped
        }
        countdownSecondsText = String(settingsService.settings.countdownSeconds)
    }

    /// Take what was typed as a speed, holding it to the range the teleprompter
    /// can scroll at. Anything that isn't a number leaves the setting alone.
    private func commitLinesPerMinute() {
        let digits = linesPerMinuteText.filter(\.isNumber)
        if let typed = Int(digits) {
            let clamped = min(max(typed, TeleprompterSettings.lpmRange.lowerBound), TeleprompterSettings.lpmRange.upperBound)
            settingsService.settings.linesPerMinute = clamped
        }
        linesPerMinuteText = String(settingsService.settings.linesPerMinute)
    }

    private func displayNameForUser(_ user: FirebaseAuth.User) -> String {
        if let displayName = user.displayName, !displayName.isEmpty {
            return displayName
        }
        if let email = user.email, email.contains("privaterelay.appleid.com") {
            return "Private User"
        }
        return "User"
    }

    /// One typed setting: the label, then the number and its unit together in
    /// a filled box. The box is what says the figure can be changed, and the
    /// unit sits inside it so what is being typed is never read bare.
    private func numberRow(label: String, text: Binding<String>, field: NumberField, unit: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            HStack(spacing: 5) {
                TextField("", text: text)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .monospacedDigit()
                    .focused($focusedField, equals: field)
                    .frame(width: 34, alignment: .trailing)
                Text(unit)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(AppColors.textSecondary(for: colorScheme).opacity(0.12))
            )
            // The unit is part of the target: tapping anywhere in the box
            // starts editing, not only the digits themselves.
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .onTapGesture { focusedField = field }
        }
        .padding(.vertical, 4)
    }

    /// Everything that shapes a run: how long before it starts, how fast the
    /// script scrolls, and the color every cue is drawn in.
    private var teleprompterSection: some View {
        Section("Teleprompter") {
            numberRow(label: "Start Delay", text: $countdownSecondsText, field: .delay, unit: "seconds")

            numberRow(label: "Scroll Speed", text: $linesPerMinuteText, field: .speed, unit: "lines/min")

            VStack(alignment: .leading, spacing: 12) {
                Text("Cue Color")

                HStack(spacing: 14) {
                    ForEach(CueColor.allCases) { option in
                        Button {
                            settingsService.settings.cueColor = option
                        } label: {
                            Circle()
                                .fill(option.color(for: colorScheme))
                                .frame(width: 28, height: 28)
                                .overlay {
                                    if option == settingsService.settings.cueColor {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 12, weight: .bold))
                                            .foregroundStyle(AppColors.background(for: colorScheme))
                                    }
                                }
                                .overlay(
                                    Circle()
                                        .stroke(
                                            AppColors.textPrimary(for: colorScheme),
                                            lineWidth: option == settingsService.settings.cueColor ? 2 : 0
                                        )
                                        .padding(-4)
                                )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(option.displayName)
                    }
                }
                .padding(.vertical, 4)

                Text("Every cue is shown in this color.")
                    .font(.footnote)
                    .foregroundStyle(AppColors.textSecondary(for: colorScheme))
            }
        }
    }

    private var inAppPrompterSection: some View {
        Section("In-App Prompter") {
            VStack(alignment: .leading, spacing: 8) {
                Text("Text Size")
                Picker("Text Size", selection: $settingsService.settings.fontSizePreset) {
                    ForEach(FontSizePreset.allCases, id: \.self) { preset in
                        Text(preset.rawValue).tag(preset)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
        }
    }

    private var floatingPrompterSection: some View {
        Section("Floating Prompter") {
            VStack(alignment: .leading, spacing: 8) {
                Text("Text Size")
                Picker("Text Size", selection: $settingsService.settings.pipFontSizePreset) {
                    ForEach(FontSizePreset.allCases, id: \.self) { preset in
                        Text(preset.rawValue).tag(preset)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Dimension Ratio")
                Picker("Dimension Ratio", selection: $settingsService.settings.overlayAspectRatio) {
                    ForEach(OverlayAspectRatio.allCases, id: \.self) { ratio in
                        Text(ratio.rawValue).tag(ratio)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
        }
    }

    private var appearanceSection: some View {
        Section("Appearance") {
            Picker("Theme", selection: $settingsService.settings.themePreference) {
                ForEach(ThemePreference.allCases, id: \.self) { theme in
                    Text(theme.rawValue).tag(theme)
                }
            }
        }
    }

    private var rateSection: some View {
        Section {
            Link(destination: ReviewPromptService.writeReviewURL) {
                VStack(alignment: .leading) {
                    HStack {
                        Text("Review on App Store")
                        Spacer()
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(AppColors.textSecondary(for: colorScheme))
                    }
                }
            }
            .foregroundStyle(AppColors.textPrimary(for: colorScheme))
            .simultaneousGesture(TapGesture().onEnded {
                AnalyticsEvents.logButtonClick("rate_app", screen: "settings")
            })
        }
    }

    private var resetSection: some View {
        Section {
            Button("Reset to Defaults") {
                AnalyticsEvents.logButtonClick("reset_to_defaults", screen: "settings")
                settingsService.resetSettings()
            }
        }
    }

    @ViewBuilder
    private var diagnosticsSection: some View {
        if isCrashlyticsTestEnabled {
            Section {
                Button(role: .destructive) {
                    AnalyticsEvents.logButtonClick("test_crash", screen: "settings")
                    Crashlytics.crashlytics().log("Manually triggered test crash")
                    fatalError("Crashlytics test crash")
                } label: {
                    Text("Trigger Test Crash")
                }
            } footer: {
                Text("This intentionally crashes the app to verify Crashlytics reporting.")
                    .font(.caption)
            }
        }
    }

    private var signOutSection: some View {
        Section {
            Button(role: .destructive) {
                AnalyticsEvents.logButtonClick("sign_out", screen: "settings")
                authService.signOut()
                dismiss()
            } label: {
                HStack {
                    Image(systemName: "rectangle.portrait.and.arrow.right")
                    Text("Sign Out")
                }
            }
            .foregroundStyle(AppColors.red(for: colorScheme))
        }
    }

    private var deleteAccountSection: some View {
        Section {
            Button(role: .destructive) {
                AnalyticsEvents.logButtonClick("delete_account", screen: "settings")
                showingDeleteConfirmation = true
            } label: {
                HStack {
                    if isDeletingAccount {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle())
                            .frame(width: 20, height: 20)
                    } else {
                        Image(systemName: "trash")
                    }
                    Text("Delete Account")
                }
            }
            .disabled(isDeletingAccount)
            .foregroundStyle(AppColors.red(for: colorScheme))
        } footer: {
            Text("This will permanently delete your account and all data stored on this device.")
                .font(.caption)
        }
    }

    private func deleteAccount() {
        isDeletingAccount = true
        Task {
            do {
                try await authService.deleteAccount()
                await MainActor.run {
                    isDeletingAccount = false
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    isDeletingAccount = false
                    deleteErrorMessage = error.localizedDescription
                }
            }
        }
    }
}

#Preview {
    SettingsView()
        .environmentObject(AuthenticationService.shared)
        .environmentObject(SettingsService.shared)
        .environmentObject(RemoteNotificationService.shared)
}
