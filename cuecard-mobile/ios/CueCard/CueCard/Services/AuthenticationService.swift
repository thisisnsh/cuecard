import Foundation
import FirebaseAuth
import FirebaseAnalytics
import GoogleSignIn
import FirebaseCore
import AuthenticationServices
import CryptoKit

@MainActor
class AuthenticationService: ObservableObject {
    static let shared = AuthenticationService()

    private let welcomeEndpoint = URL(string: "https://cuecard-mobile.thisisnsh.workers.dev/welcome")

    @Published var user: User?
    @Published var isAuthenticated = false
    @Published var isLoading = false
    @Published var errorMessage: String?

    /// Tracks the current sign-in provider for account operations
    private(set) var currentSignInProvider: String?

    /// Current nonce for Apple Sign-In (used for security)
    private var currentNonce: String?

    private init() {
        // Listen for auth state changes
        Auth.auth().addStateDidChangeListener { [weak self] _, user in
            self?.user = user
            self?.isAuthenticated = user != nil

            if let user = user {
                Analytics.setUserID(user.uid)
                Analytics.logEvent(AnalyticsEventLogin, parameters: [
                    AnalyticsParameterMethod: "google"
                ])
            }
        }
    }

    func signInWithGoogle() async {
        guard let clientID = FirebaseApp.app()?.options.clientID else {
            errorMessage = "Firebase configuration error"
            return
        }

        let config = GIDConfiguration(clientID: clientID)
        GIDSignIn.sharedInstance.configuration = config

        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootViewController = windowScene.windows.first?.rootViewController else {
            errorMessage = "Unable to get root view controller"
            return
        }

        isLoading = true
        errorMessage = nil

        do {
            let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: rootViewController)

            guard let idToken = result.user.idToken?.tokenString else {
                errorMessage = "Unable to get ID token"
                isLoading = false
                return
            }

            let credential = GoogleAuthProvider.credential(
                withIDToken: idToken,
                accessToken: result.user.accessToken.tokenString
            )

            let authResult = try await Auth.auth().signIn(with: credential)

            currentSignInProvider = "google"
            Analytics.logEvent("sign_in_success", parameters: ["method": "google"])
            await sendWelcome(
                authResult: authResult,
                provider: "google"
            )
        } catch {
            errorMessage = error.localizedDescription
            Analytics.logEvent("sign_in_error", parameters: [
                "error": error.localizedDescription
            ])
        }

        isLoading = false
    }

    // MARK: - Sign in with Apple

    func signInWithApple() {
        isLoading = true
        errorMessage = nil

        let nonce = randomNonceString()
        currentNonce = nonce

        let appleIDProvider = ASAuthorizationAppleIDProvider()
        let request = appleIDProvider.createRequest()
        request.requestedScopes = [.fullName, .email]
        request.nonce = sha256(nonce)

        let authorizationController = ASAuthorizationController(authorizationRequests: [request])
        let delegate = AppleSignInDelegate(service: self)
        appleSignInDelegate = delegate
        authorizationController.delegate = delegate
        authorizationController.presentationContextProvider = delegate
        authorizationController.performRequests()
    }

    /// Stored delegate reference to prevent deallocation
    private var appleSignInDelegate: AppleSignInDelegate?

    /// Called by the delegate when Apple Sign-In completes
    fileprivate func handleAppleSignInResult(_ result: Result<ASAuthorization, Error>) async {
        defer {
            isLoading = false
            appleSignInDelegate = nil
        }

        switch result {
        case .success(let authorization):
            guard let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let appleIDToken = appleIDCredential.identityToken,
                  let idTokenString = String(data: appleIDToken, encoding: .utf8),
                  let nonce = currentNonce else {
                errorMessage = "Unable to fetch identity token"
                return
            }

            let credential = OAuthProvider.appleCredential(
                withIDToken: idTokenString,
                rawNonce: nonce,
                fullName: appleIDCredential.fullName
            )

            do {
                let authResult = try await Auth.auth().signIn(with: credential)
                currentSignInProvider = "apple"
                Analytics.logEvent("sign_in_success", parameters: ["method": "apple"])
                await sendWelcome(
                    authResult: authResult,
                    provider: "apple",
                    fullName: appleIDCredential.fullName,
                    emailOverride: appleIDCredential.email
                )
            } catch {
                errorMessage = error.localizedDescription
                Analytics.logEvent("sign_in_error", parameters: [
                    "error": error.localizedDescription,
                    "method": "apple"
                ])
            }

        case .failure(let error):
            // User cancelled - don't show error
            if (error as NSError).code == ASAuthorizationError.canceled.rawValue {
                return
            }
            errorMessage = error.localizedDescription
            Analytics.logEvent("sign_in_error", parameters: [
                "error": error.localizedDescription,
                "method": "apple"
            ])
        }
    }

    // MARK: - Nonce Generation

    private func randomNonceString(length: Int = 32) -> String {
        precondition(length > 0)
        var randomBytes = [UInt8](repeating: 0, count: length)
        let errorCode = SecRandomCopyBytes(kSecRandomDefault, randomBytes.count, &randomBytes)
        if errorCode != errSecSuccess {
            fatalError("Unable to generate nonce. SecRandomCopyBytes failed with OSStatus \(errorCode)")
        }

        let charset: [Character] = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        let nonce = randomBytes.map { byte in
            charset[Int(byte) % charset.count]
        }
        return String(nonce)
    }

    private func sha256(_ input: String) -> String {
        let inputData = Data(input.utf8)
        let hashedData = SHA256.hash(data: inputData)
        let hashString = hashedData.compactMap {
            String(format: "%02x", $0)
        }.joined()
        return hashString
    }

    // MARK: - Welcome Email Request

    private struct WelcomePayload: Encodable {
        let uid: String
        let email: String?
        let displayName: String?
        let provider: String?
        let createdAt: String?
    }

    private func sendWelcome(
        authResult: AuthDataResult,
        provider: String,
        fullName: PersonNameComponents? = nil,
        emailOverride: String? = nil
    ) async {
        guard let url = welcomeEndpoint else {
            Analytics.logEvent("welcome_request_error", parameters: [
                "error": "invalid_url",
                "provider": provider
            ])
            return
        }

        let nameFormatter = PersonNameComponentsFormatter()
        let formattedName = fullName.map { nameFormatter.string(from: $0) }
        let user = authResult.user
        let createdAt = user.metadata.creationDate.map {
            ISO8601DateFormatter().string(from: $0)
        }

        let payload = WelcomePayload(
            uid: user.uid,
            email: emailOverride ?? user.email,
            displayName: formattedName ?? user.displayName,
            provider: provider,
            createdAt: createdAt
        )

        do {
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(payload)

            let (_, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse,
               (200..<300).contains(httpResponse.statusCode) {
                Analytics.logEvent("welcome_request_success", parameters: [
                    "provider": provider
                ])
            } else {
                Analytics.logEvent("welcome_request_error", parameters: [
                    "error": "bad_status",
                    "provider": provider
                ])
            }
        } catch {
            Analytics.logEvent("welcome_request_error", parameters: [
                "error": error.localizedDescription,
                "provider": provider
            ])
        }
    }

    // MARK: - Sign Out

    func signOut() {
        do {
            try Auth.auth().signOut()
            GIDSignIn.sharedInstance.signOut()
            currentSignInProvider = nil
            Analytics.logEvent("sign_out", parameters: nil)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Account Deletion

    func deleteAccount() async throws {
        guard let user = Auth.auth().currentUser else {
            throw AuthError.noUser
        }

        do {
            // Delete the Firebase user account
            try await user.delete()

            // Sign out of Google if applicable
            GIDSignIn.sharedInstance.signOut()

            // Clear all local data
            await MainActor.run {
                SettingsService.shared.clearAllData()
            }

            currentSignInProvider = nil
            Analytics.logEvent("account_deleted", parameters: nil)
        } catch let error as NSError {
            // Check if re-authentication is required
            if error.code == AuthErrorCode.requiresRecentLogin.rawValue {
                throw AuthError.requiresRecentLogin
            }
            throw error
        }
    }

    enum AuthError: LocalizedError {
        case noUser
        case requiresRecentLogin

        var errorDescription: String? {
            switch self {
            case .noUser:
                return "No user is currently signed in."
            case .requiresRecentLogin:
                return "Please sign out and sign in again before deleting your account."
            }
        }
    }
}

// MARK: - Apple Sign-In Delegate

private class AppleSignInDelegate: NSObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
    private weak var service: AuthenticationService?

    init(service: AuthenticationService) {
        self.service = service
    }

    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = windowScene.windows.first else {
            fatalError("No window found")
        }
        return window
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        Task { @MainActor in
            await service?.handleAppleSignInResult(.success(authorization))
        }
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        Task { @MainActor in
            await service?.handleAppleSignInResult(.failure(error))
        }
    }
}
