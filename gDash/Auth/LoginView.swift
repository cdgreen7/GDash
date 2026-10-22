import AuthenticationServices
import SwiftUI

struct LoginView: View {
    @Environment(AuthManager.self) private var auth
    @State private var appeared = false

    private let orbit: [HubSection] = [.assignments, .calendar, .habits, .finances]

    var body: some View {
        ZStack {
            HubBackground(accent: HubSection.assignments.tint)

            VStack(alignment: .leading, spacing: 0) {
                Spacer()

                HStack(spacing: -12) {
                    ForEach(Array(orbit.enumerated()), id: \.element) { index, section in
                        IconBadge(systemName: section.icon, colors: section.colors, size: 58)
                            .rotationEffect(.degrees(appeared ? Double(index * 6 - 9) : 0))
                            .offset(y: appeared ? CGFloat(index % 2 == 0 ? -6 : 6) : 30)
                            .opacity(appeared ? 1 : 0)
                            .animation(.spring(response: 0.7, dampingFraction: 0.6).delay(Double(index) * 0.08), value: appeared)
                    }
                }
                .padding(.bottom, 36)

                Text("Your life,\none hub.")
                    .font(.display(54))
                    .foregroundStyle(.white)
                Text("Assignments, schedule, habits and money in one private place, synced only to your iCloud.")
                    .font(.body)
                    .foregroundStyle(Theme.secondary)
                    .padding(.top, 14)

                Spacer()

                VStack(spacing: 14) {
                    SignInWithAppleButton(.continue) { request in
                        request.requestedScopes = [.fullName]
                    } onCompletion: { result in
                        auth.handleSignIn(result)
                    }
                    .signInWithAppleButtonStyle(.white)
                    .frame(height: 56)
                    .clipShape(Capsule())

                    #if DEBUG
                    Button("Use local test account") { auth.signInLocalTestAccount() }
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Theme.secondary)
                    #endif

                    if let message = auth.errorMessage {
                        Text(message).font(.footnote).foregroundStyle(Theme.danger)
                    }

                    Label("Secured by Sign in with Apple and Face ID", systemImage: "lock.shield.fill")
                        .font(.caption)
                        .foregroundStyle(Theme.tertiary)
                }
            }
            .padding(24)
        }
        .onAppear { appeared = true }
    }
}

struct LockView: View {
    @Environment(AuthManager.self) private var auth

    var body: some View {
        ZStack {
            HubBackground(accent: HubSection.calendar.tint)

            VStack(spacing: 18) {
                Spacer()
                Image(systemName: "lock.fill")
                    .font(.system(size: 34, weight: .bold))
                    .frame(width: 96, height: 96)
                    .glassEffect(.regular.tint(HubSection.calendar.tint.opacity(0.25)), in: .circle)
                Text(auth.firstName.isEmpty ? "Welcome back" : "Welcome back,\n\(auth.firstName)")
                    .font(.display(38))
                    .multilineTextAlignment(.center)
                Text("Your hub is locked")
                    .foregroundStyle(Theme.secondary)
                if let message = auth.errorMessage {
                    Text(message).font(.footnote).foregroundStyle(Theme.danger)
                }
                Spacer()

                Button {
                    Task { await auth.unlock() }
                } label: {
                    Label("Unlock with \(auth.biometryName)", systemImage: auth.biometryIcon)
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                }
                .buttonStyle(.glassProminent)

                Button("Sign out") { auth.signOut() }
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.secondary)
            }
            .padding(24)
        }
    }
}
