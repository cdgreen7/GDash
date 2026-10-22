import CryptoKit
import Foundation
import SwiftData

enum HubError: LocalizedError {
    case notSignedIn
    case notFound(String)

    var errorDescription: String? {
        switch self {
        case .notSignedIn: "Open gDash and sign in first."
        case .notFound(let what): "Couldn't find \(what)."
        }
    }
}

/// Owns one SwiftData store per signed-in account. Each store syncs to the user's private
/// iCloud database when the CloudKit entitlement is present, and stays local otherwise.
@MainActor
final class DataStore {
    static let shared = DataStore()

    static let schema = Schema([
        Assignment.self, HubEvent.self, Habit.self, HabitLog.self,
        Budget.self, MoneyEntry.self, Bill.self,
    ])

    private var containers: [String: ModelContainer] = [:]

    func container(for userID: String) throws -> ModelContainer {
        if let cached = containers[userID] { return cached }

        // Hash the account ID so the store's file name doesn't reveal it.
        let digest = SHA256.hash(data: Data(userID.utf8)).prefix(8).map { String(format: "%02x", $0) }.joined()
        let directory = URL.applicationSupportDirectory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let configuration = ModelConfiguration(
            "gDash-\(digest)",
            schema: Self.schema,
            url: directory.appending(path: "gDash-\(digest).store"),
            cloudKitDatabase: .automatic
        )
        let container = try ModelContainer(for: Self.schema, configurations: configuration)
        containers[userID] = container
        return container
    }

    /// The store for whoever is signed in. Used by App Intents, which run without the UI.
    func currentContainer() throws -> ModelContainer {
        guard let userID = Keychain.string(for: AuthManager.userIDKey) else { throw HubError.notSignedIn }
        return try container(for: userID)
    }
}
