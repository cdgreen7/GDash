import AppIntents
import SwiftData

// Actions exposed to the Shortcuts app and Siri. They all require the device to be unlocked
// and run against the signed-in account's store.

struct HabitEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Habit"
    static let defaultQuery = HabitQuery()

    let id: UUID
    let name: String

    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }

    init(_ habit: Habit) {
        id = habit.id
        name = habit.name
    }
}

struct HabitQuery: EntityStringQuery {
    @MainActor
    private func allHabits() throws -> [Habit] {
        try DataStore.shared.currentContainer().mainContext.fetch(FetchDescriptor<Habit>(sortBy: [SortDescriptor(\.createdAt)]))
    }

    @MainActor
    func entities(for identifiers: [UUID]) async throws -> [HabitEntity] {
        try allHabits().filter { identifiers.contains($0.id) }.map(HabitEntity.init)
    }

    @MainActor
    func entities(matching string: String) async throws -> [HabitEntity] {
        try allHabits().filter { $0.name.localizedCaseInsensitiveContains(string) }.map(HabitEntity.init)
    }

    @MainActor
    func suggestedEntities() async throws -> [HabitEntity] {
        try allHabits().map(HabitEntity.init)
    }
}

struct LogHabitIntent: AppIntent {
    static let title: LocalizedStringResource = "Log Habit"
    static let description = IntentDescription("Mark a habit as done for today.")
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication

    @Parameter(title: "Habit")
    var habit: HabitEntity

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let context = try DataStore.shared.currentContainer().mainContext
        let id = habit.id
        guard let model = try context.fetch(FetchDescriptor<Habit>(predicate: #Predicate { $0.id == id })).first else {
            throw HubError.notFound(habit.name)
        }
        HubActions.setHabit(model, logged: true, in: context)
        return .result(dialog: "Logged \(model.name). You're on a \(model.currentStreak)-day streak.")
    }
}

struct AddAssignmentIntent: AppIntent {
    static let title: LocalizedStringResource = "Add Assignment"
    static let description = IntentDescription("Add an assignment or task with a due date.")
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication

    @Parameter(title: "Title")
    var title: String

    @Parameter(title: "Due Date")
    var dueDate: Date

    @Parameter(title: "Course")
    var course: String?

    @Parameter(title: "High Priority", default: false)
    var highPriority: Bool

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let context = try DataStore.shared.currentContainer().mainContext
        HubActions.addAssignment(title: title, course: course ?? "", due: dueDate,
                                 priority: highPriority ? .high : .medium, in: context)
        return .result(dialog: "Added \(title), due \(dueDate.dueDescription).")
    }
}

struct AddEventIntent: AppIntent {
    static let title: LocalizedStringResource = "Add Calendar Event"
    static let description = IntentDescription("Put an event on your gDash schedule.")
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication

    @Parameter(title: "Title")
    var title: String

    @Parameter(title: "Start")
    var start: Date

    @Parameter(title: "Duration (minutes)", default: 60)
    var duration: Int

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let context = try DataStore.shared.currentContainer().mainContext
        HubActions.addEvent(title: title, start: start, end: start.addingTimeInterval(Double(max(duration, 5)) * 60), in: context)
        return .result(dialog: "Scheduled \(title) for \(start.dueDescription).")
    }
}

struct LogMoneyIntent: AppIntent {
    static let title: LocalizedStringResource = "Log Expense or Income"
    static let description = IntentDescription("Record spending against a budget, or income.")
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication

    @Parameter(title: "Amount")
    var amount: Double

    @Parameter(title: "Description")
    var title: String

    @Parameter(title: "Category")
    var category: String?

    @Parameter(title: "Is Income", default: false)
    var isIncome: Bool

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let context = try DataStore.shared.currentContainer().mainContext
        HubActions.addEntry(title: title, amount: amount, isIncome: isIncome,
                            category: category ?? (isIncome ? "Income" : "Uncategorized"), in: context)
        return .result(dialog: "Recorded \(isIncome ? "income" : "expense") of \(amount.currency).")
    }
}

struct WhatNextIntent: AppIntent {
    static let title: LocalizedStringResource = "What Should I Do Next"
    static let description = IntentDescription("Get your most urgent open item across assignments, habits, bills and events.")
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ReturnsValue<String> {
        let context = try DataStore.shared.currentContainer().mainContext
        guard let top = NextUpEngine.rank(in: context).first else {
            return .result(value: "Nothing", dialog: "You're all caught up!")
        }
        return .result(value: top.title, dialog: "Next up: \(top.title). \(top.detail).")
    }
}

struct GDashShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: LogHabitIntent(), phrases: [
            "Log a habit in \(.applicationName)",
            "Log \(\.$habit) in \(.applicationName)",
        ], shortTitle: "Log Habit", systemImageName: "flame.fill")

        AppShortcut(intent: AddAssignmentIntent(), phrases: [
            "Add an assignment in \(.applicationName)",
            "Add a task to \(.applicationName)",
        ], shortTitle: "Add Assignment", systemImageName: "checklist")

        AppShortcut(intent: AddEventIntent(), phrases: [
            "Add an event to \(.applicationName)",
        ], shortTitle: "Add Event", systemImageName: "calendar.badge.plus")

        AppShortcut(intent: LogMoneyIntent(), phrases: [
            "Log spending in \(.applicationName)",
        ], shortTitle: "Log Money", systemImageName: "dollarsign.circle")

        AppShortcut(intent: WhatNextIntent(), phrases: [
            "What should I do next in \(.applicationName)",
            "Ask \(.applicationName) what's next",
        ], shortTitle: "What's Next", systemImageName: "sparkles")
    }
}
