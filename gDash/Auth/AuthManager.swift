import AuthenticationServices
import LocalAuthentication
import SwiftUI

/// Sign in with Apple establishes the account; Face ID / passcode gates every return to the app.
@MainActor
@Observable
final class AuthManager {
    enum State: Equatable {
        case checking
        case signedOut
        case locked(String)
        case unlocked(String)

        var isUnlocked: Bool {
            if case .unlocked = self { return true }
            return false
        }
    }

    static let userIDKey = "account.userID"
    private static let biometricsDefaultsKey = "requireBiometrics"

    var state: State = .checking
    var displayName = ""
    var errorMessage: String?
    /// Set when the app is locked on backgrounding so we prompt once on return, not in a loop.
    var pendingAutoUnlock = false

    var requireBiometrics: Bool {
        didSet { UserDefaults.standard.set(requireBiometrics, forKey: Self.biometricsDefaultsKey) }
    }

    init() {
        requireBiometrics = UserDefaults.standard.object(forKey: Self.biometricsDefaultsKey) as? Bool ?? true
    }

    var firstName: String {
        displayName.split(separator: " ").first.map(String.init) ?? ""
    }

    var biometryName: String {
        switch LAContext().biometryType {
        case .faceID: "Face ID"
        case .touchID: "Touch ID"
        case .opticID: "Optic ID"
        default: "Passcode"
        }
    }

    var biometryIcon: String {
        switch LAContext().biometryType {
        case .faceID: "faceid"
        case .touchID: "touchid"
        case .opticID: "opticid"
        default: "lock.fill"
        }
    }

    func bootstrap() async {
        guard state == .checking else { return }
        guard let userID = Keychain.string(for: Self.userIDKey) else {
            state = .signedOut
            return
        }
        displayName = Keychain.string(for: "name.\(userID)") ?? ""

        // If the user revoked this app in their Apple ID settings, end the session.
        if !userID.hasPrefix("local-"),
           let credential = try? await ASAuthorizationAppleIDProvider().credentialState(forUserID: userID),
           credential == .revoked {
            signOut()
            return
        }

        if requireBiometrics {
            state = .locked(userID)
            await unlock()
        } else {
            state = .unlocked(userID)
        }
    }

    func handleSignIn(_ result: Result<ASAuthorization, Error>) {
        errorMessage = nil
        switch result {
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else { return }
            // Apple only sends the name the first time the user signs in.
            if let components = credential.fullName {
                let name = PersonNameComponentsFormatter().string(from: components)
                if !name.isEmpty { Keychain.set(name, for: "name.\(credential.user)") }
            }
            completeSignIn(userID: credential.user)
        case .failure(let error):
            if (error as? ASAuthorizationError)?.code != .canceled {
                errorMessage = error.localizedDescription
            }
        }
    }

    #if DEBUG
    /// Simulators without an Apple Account can't complete Sign in with Apple.
    func signInLocalTestAccount() {
        Keychain.set("Test User", for: "name.local-test")
        completeSignIn(userID: "local-test")
    }
    #endif

    private func completeSignIn(userID: String) {
        Keychain.set(userID, for: Self.userIDKey)
        displayName = Keychain.string(for: "name.\(userID)") ?? ""
        state = .unlocked(userID)
    }

    func unlock() async {
        guard case .locked(let userID) = state else { return }
        let context = LAContext()
        var policyError: NSError?
        // A device with no passcode can't be protected; let the user in rather than lock them out.
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &policyError) else {
            state = .unlocked(userID)
            return
        }
        do {
            if try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Unlock your gDash hub") {
                errorMessage = nil
                state = .unlocked(userID)
            }
        } catch {
            if (error as? LAError)?.code != .userCancel {
                errorMessage = error.localizedDescription
            }
        }
    }

    func lock() {
        guard requireBiometrics, case .unlocked(let userID) = state else { return }
        state = .locked(userID)
        pendingAutoUnlock = true
    }

    func signOut() {
        Keychain.delete(Self.userIDKey)
        displayName = ""
        state = .signedOut
    }
}
