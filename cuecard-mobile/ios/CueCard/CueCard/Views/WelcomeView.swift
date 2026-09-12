import SwiftUI
import FirebaseAnalytics

/// The first thing a new install opens on. Tapping through remembers itself, so
/// this is seen once: only a fresh install brings it back.
struct WelcomeView: View {
    @EnvironmentObject var settingsService: SettingsService
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        ZStack {
            // Background
            AppColors.background(for: colorScheme)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                // Hero section
                VStack(spacing: 24) {
                    // Logo
                    Image("Icon")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 80, height: 80)
                        .clipShape(RoundedRectangle(cornerRadius: 16))

                    // Title
                    VStack(spacing: 8) {
                        Text("CueCard")
                            .font(.system(size: 36, weight: .bold))
                            .foregroundStyle(AppColors.textPrimary(for: colorScheme))

                        Text("Floating Teleprompter")
                            .font(.title3)
                            .fontWeight(.medium)
                            .foregroundStyle(AppColors.textSecondary(for: colorScheme))
                    }
                }
                .frame(maxWidth: .infinity)

                Spacer()

                // Get started section
                VStack(spacing: 16) {
                    
                    Button(action: {
                        AnalyticsEvents.logButtonClick("get_started", screen: "welcome")
                        settingsService.completeWelcome()
                    }) {
                        Text("Get Started")
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(colorScheme == .dark ? Color.white : Color.black)
                            )
                            .foregroundStyle(colorScheme == .dark ? Color.black : Color.white)
                            .shadow(color: .black.opacity(0.1), radius: 4, y: 2)
                    }

                    // Privacy note
                    VStack(spacing: 6) {
                        Text("No account needed. Scripts stay on this device.")

                        HStack(spacing: 16) {
                            Link(destination: AppLinks.privacyPolicy) {
                                HStack(spacing: 4) {
                                    Text("Privacy policy")
                                        .underline()
                                    Image(systemName: "arrow.up.right")
                                        .font(.system(size: 9, weight: .semibold))
                                }
                            }
                            .simultaneousGesture(TapGesture().onEnded {
                                AnalyticsEvents.logButtonClick("privacy_policy", screen: "welcome")
                            })

                            Link(destination: AppLinks.sourceCode) {
                                HStack(spacing: 4) {
                                    Text("View code")
                                        .underline()
                                    Image(systemName: "arrow.up.right")
                                        .font(.system(size: 9, weight: .semibold))
                                }
                            }
                            .simultaneousGesture(TapGesture().onEnded {
                                AnalyticsEvents.logButtonClick("source_code", screen: "welcome")
                            })
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(AppColors.textSecondary(for: colorScheme))
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 48)
            }
        }
        .onAppear {
            Analytics.logEvent(AnalyticsEventScreenView, parameters: [
                AnalyticsParameterScreenName: "welcome"
            ])
        }
    }
}

#Preview {
    WelcomeView()
        .environmentObject(SettingsService.shared)
}
