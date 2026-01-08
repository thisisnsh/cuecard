import SwiftUI
import FirebaseAnalytics
import FirebaseCrashlytics

struct SettingsView: View {
    @EnvironmentObject var authService: AuthenticationService
    @EnvironmentObject var settingsService: SettingsService
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme

    @State private var showingDeleteConfirmation = false
    @State private var isDeletingAccount = false
    @State private var deleteErrorMessage: String?

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
            Analytics.logEvent(AnalyticsEventScreenView, parameters: [
                AnalyticsParameterScreenName: "settings"
            ])
        }
    }

    private var settingsList: some View {
        List {
            userInfoSection
            countdownSection
            teleprompterSection
            textSizeSection
            overlaySection
            appearanceSection
            resetSection
            diagnosticsSection
            signOutSection
            deleteAccountSection
        }
    }

    @ViewBuilder
    private var userInfoSection: some View {
        if let user = authService.user {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    if let displayName = user.displayName, !displayName.isEmpty {
                        Text(displayName)
                            .font(.headline)
                    }

                    if let email = user.email {
                        Text(email)
                            .font(.subheadline)
                            .foregroundStyle(user.displayName != nil && !user.displayName!.isEmpty ? .secondary : .primary)
                    }
                }
                .padding(.vertical, 8)
            }
        }
    }

    private var countdownSection: some View {
        Section("Countdown") {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Start Delay")
                    Spacer()
                    Text("\(settingsService.settings.countdownSeconds) seconds")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }

                Slider(
                    value: Binding(
                        get: { Double(settingsService.settings.countdownSeconds) },
                        set: { settingsService.settings.countdownSeconds = Int($0) }
                    ),
                    in: 0...10,
                    step: 1
                )
            }
            .padding(.vertical, 4)
        }
    }

    private var teleprompterSection: some View {
        Section("Teleprompter") {
            Toggle("Highlight Words", isOn: $settingsService.settings.autoScroll)

            if settingsService.settings.autoScroll {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Highlight Speed")
                        Spacer()
                        Text("\(settingsService.settings.wordsPerMinute) WPM")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }

                    Slider(
                        value: Binding(
                            get: { Double(settingsService.settings.wordsPerMinute) },
                            set: { settingsService.settings.wordsPerMinute = Int($0) }
                        ),
                        in: Double(TeleprompterSettings.wpmRange.lowerBound)...Double(TeleprompterSettings.wpmRange.upperBound),
                        step: 10
                    )
                }
                .padding(.vertical, 4)
            }
        }
    }

    private var textSizeSection: some View {
        Section("Text Size") {
            VStack(alignment: .leading, spacing: 8) {
                Text("App Text Size")
                Picker("App Text Size", selection: $settingsService.settings.fontSizePreset) {
                    ForEach(FontSizePreset.allCases, id: \.self) { preset in
                        Text(preset.rawValue).tag(preset)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Overlay Text Size")
                Picker("Overlay Text Size", selection: $settingsService.settings.pipFontSizePreset) {
                    ForEach(FontSizePreset.allCases, id: \.self) { preset in
                        Text(preset.rawValue).tag(preset)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
        }
    }

    private var overlaySection: some View {
        Section("Overlay") {
            VStack(alignment: .leading, spacing: 8) {
                Text("Overlay Dimension Ratio")
                Picker("Overlay Dimension Ratio", selection: $settingsService.settings.overlayAspectRatio) {
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
}
