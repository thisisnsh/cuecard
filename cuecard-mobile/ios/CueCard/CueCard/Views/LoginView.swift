import SwiftUI
import AuthenticationServices
import FirebaseAnalytics
import FirebaseCrashlytics

struct LoginView: View {
    @EnvironmentObject var authService: AuthenticationService
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

                // Error message
                if let error = authService.errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(AppColors.red(for: colorScheme))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                        .padding(.bottom, 16)
                }

                // Sign in section
                VStack(spacing: 16) {
                    // Sign in with Apple button
                    SignInWithAppleButton(.signIn) { request in
                        request.requestedScopes = [.fullName, .email]
                    } onCompletion: { _ in
                        // Handled by AuthenticationService
                    }
                    .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
                    .frame(height: 50)
                    .cornerRadius(12)
                    .disabled(authService.isLoading)
                    .opacity(authService.isLoading ? 0.6 : 1)
                    .onTapGesture {
                        AnalyticsEvents.logButtonClick("sign_in_with_apple", screen: "login")
                        authService.signInWithApple()
                    }
                    .allowsHitTesting(!authService.isLoading)

                    // Google Sign in button
                    Button(action: {
                        AnalyticsEvents.logButtonClick("sign_in_with_google", screen: "login")
                        Task {
                            await authService.signInWithGoogle()
                        }
                    }) {
                        HStack(spacing: 12) {
                            Image("GoogleLogo")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 20, height: 20)

                            Text("Continue with Google")
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.white)
                        )
                        .foregroundStyle(.black)
                        .shadow(color: .black.opacity(0.1), radius: 4, y: 2)
                    }
                    .disabled(authService.isLoading)
                    .opacity(authService.isLoading ? 0.6 : 1)

                    if authService.isLoading {
                        ProgressView()
                            .tint(AppColors.green(for: colorScheme))
                    }

                    // Privacy note
                    Text("Your data stays on your device")
                        .font(.caption)
                        .foregroundStyle(AppColors.textSecondary(for: colorScheme))
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 48)
            }
        }
    }
}

/// Feature row for login screen
struct FeatureRow: View {
    let icon: String
    let title: String
    let description: String
    let colorScheme: ColorScheme

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundStyle(AppColors.green(for: colorScheme))
                .frame(width: 40, height: 40)
                .background(
                    Circle()
                        .fill(AppColors.green(for: colorScheme).opacity(0.15))
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(AppColors.textPrimary(for: colorScheme))

                Text(description)
                    .font(.caption)
                    .foregroundStyle(AppColors.textSecondary(for: colorScheme))
            }
        }
    }
}

#Preview {
    LoginView()
        .environmentObject(AuthenticationService.shared)
}
