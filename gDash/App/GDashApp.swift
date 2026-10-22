import SwiftUI

@main
struct GDashApp: App {
    @State private var auth = AuthManager()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(auth)
                .preferredColorScheme(.dark)
                .tint(HubSection.assistant.tint)
        }
    }
}

struct RootView: View {
    @Environment(AuthManager.self) private var auth
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            switch auth.state {
            case .checking:
                HubBackground()
            case .signedOut:
                LoginView().transition(.opacity)
            case .locked:
                LockView().transition(.opacity)
            case .unlocked(let userID):
                UnlockedHub(userID: userID)
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            }

            if scenePhase != .active, auth.state.isUnlocked {
                PrivacyShield()
            }
        }
        .animation(.smooth(duration: 0.4), value: auth.state)
        .task { await auth.bootstrap() }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .background:
                auth.lock()
            case .active where auth.pendingAutoUnlock:
                auth.pendingAutoUnlock = false
                Task { await auth.unlock() }
            default:
                break
            }
        }
    }
}

private struct UnlockedHub: View {
    let userID: String

    var body: some View {
        if let container = try? DataStore.shared.container(for: userID) {
            HubShell()
                .modelContainer(container)
                .task { GDashShortcuts.updateAppShortcutParameters() }
        } else {
            ContentUnavailableView("Couldn't open your data",
                                   systemImage: "externaldrive.badge.exclamationmark",
                                   description: Text("Try signing out and back in."))
        }
    }
}
