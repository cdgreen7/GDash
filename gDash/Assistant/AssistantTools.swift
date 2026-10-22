import Foundation
import FoundationModels
import SwiftData

/// Collects what the tools changed so the chat can show confirmation chips under each reply.
@MainActor
final class ToolActivity {
    private(set) var notes: [String] = []

    func record(_ note: String) { notes.append(note) }

    func drain() -> [String] {
        defer { notes = [] }
        return notes
    }
}

enum AssistantDate {
    private static let formats = ["yyyy-MM-dd HH:mm", "yyyy-MM-dd'T'HH:mm", "yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd"]

    static func parse(_ text: String?) -> Date? {
        guard let text = text?.trimmingCharacters(in: .whitespaces), !text.isEmpty else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        for format in formats {
            formatter.dateFormat = format
            if let date = formatter.date(from: text) {
                // A bare date means end of that day for deadlines.
                return format == "yyyy-MM-dd" ? Calendar.current.date(bySettingHour: 23, minute: 59, second: 0, of: date) : date
            }
        }
        return nil
    }

    static var now: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEEE yyyy-MM-dd HH:mm"
        return formatter.string(from: .now)
    }

    static var tomorrowEvening: Date {
        Calendar.current.date(bySettingHour: 23, minute: 59, second: 0,
                              of: Calendar.current.date(byAdding: .day, value: 1, to: .now)!)!
    }

    static func describe(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day().hour().minute())
    }
}

// MARK: - Tools

struct AddAssignmentTool: Tool {
    let name = "addAssignment"
    let description = "Create an assignment or to-do task with a due date."
    let container: ModelContainer
    let activity: ToolActivity

    @Generable
    struct Arguments {
        @Guide(description: "Short title of the task")
        var title: String
        @Guide(description: "Course or project name, or empty")
        var course: String?
        @Guide(description: "Due date as yyyy-MM-dd HH:mm local time")
        var due: String?
        @Guide(description: "true if the user says it is important or urgent")
        var highPriority: Bool?
    }

    func call(arguments: Arguments) async throws -> String {
        await MainActor.run {
            let due = AssistantDate.parse(arguments.due) ?? AssistantDate.tomorrowEvening
            let assignment = HubActions.addAssignment(
                title: arguments.title, course: arguments.course ?? "", due: due,
                priority: arguments.highPriority == true ? .high : .medium, in: container.mainContext)
            activity.record("Added “\(assignment.title)” · due \(due.dueDescription)")
            return "Added assignment \(assignment.title), due \(AssistantDate.describe(due))."
        }
    }
}

struct AddEventTool: Tool {
    let name = "addEvent"
    let description = "Put an event, appointment or habit check-in on the calendar."
    let container: ModelContainer
    let activity: ToolActivity

    @Generable
    struct Arguments {
        @Guide(description: "Event title")
        var title: String
        @Guide(description: "Start as yyyy-MM-dd HH:mm local time")
        var start: String
        @Guide(description: "Length in minutes, default 60")
        var durationMinutes: Int?
        @Guide(description: "One of: personal, work, school, habit, other")
        var category: String?
    }

    func call(arguments: Arguments) async throws -> String {
        await MainActor.run {
            guard let start = AssistantDate.parse(arguments.start) else {
                return "Couldn't understand the start time \(arguments.start). Ask the user when it starts."
            }
            let minutes = max(arguments.durationMinutes ?? 60, 5)
            let kind = EventKind(rawValue: arguments.category?.lowercased() ?? "") ?? .personal
            HubActions.addEvent(title: arguments.title, start: start, end: start.addingTimeInterval(Double(minutes) * 60),
                                kind: kind, in: container.mainContext)
            activity.record("Scheduled “\(arguments.title)” · \(start.dueDescription)")
            return "Scheduled \(arguments.title) on \(AssistantDate.describe(start)) for \(minutes) minutes."
        }
    }
}

struct LogHabitTool: Tool {
    let name = "logHabit"
    let description = "Mark one of the user's habits as done today."
    let container: ModelContainer
    let activity: ToolActivity

    @Generable
    struct Arguments {
        @Guide(description: "Name of the habit")
        var habit: String
    }

    func call(arguments: Arguments) async throws -> String {
        await MainActor.run {
            let context = container.mainContext
            guard let habit = HubActions.habit(named: arguments.habit, in: context) else {
                let names = ((try? context.fetch(FetchDescriptor<Habit>())) ?? []).map(\.name)
                return "No habit called \(arguments.habit). Existing habits: \(names.joined(separator: ", "))."
            }
            HubActions.setHabit(habit, logged: true, in: context)
            activity.record("Logged \(habit.name) · \(habit.currentStreak)-day streak")
            return "Logged \(habit.name). Current streak is \(habit.currentStreak) days."
        }
    }
}

struct SetBudgetTool: Tool {
    let name = "setBudget"
    let description = "Create a monthly budget category or change its limit."
    let container: ModelContainer
    let activity: ToolActivity

    @Generable
    struct Arguments {
        @Guide(description: "Budget category, e.g. Groceries")
        var category: String
        @Guide(description: "Monthly limit in the user's currency")
        var monthlyLimit: Double
    }

    func call(arguments: Arguments) async throws -> String {
        await MainActor.run {
            let budget = HubActions.setBudget(category: arguments.category, limit: arguments.monthlyLimit, in: container.mainContext)
            activity.record("\(budget.name) budget → \(budget.limit.currency)/mo")
            return "\(budget.name) budget is now \(budget.limit.currency) per month."
        }
    }
}

struct RecordMoneyTool: Tool {
    let name = "recordMoney"
    let description = "Record an expense or income."
    let container: ModelContainer
    let activity: ToolActivity

    @Generable
    struct Arguments {
        @Guide(description: "What it was, e.g. Coffee")
        var title: String
        @Guide(description: "Positive amount")
        var amount: Double
        @Guide(description: "true for income, false for spending")
        var isIncome: Bool
        @Guide(description: "Budget category for spending, e.g. Dining")
        var category: String?
    }

    func call(arguments: Arguments) async throws -> String {
        await MainActor.run {
            let entry = HubActions.addEntry(
                title: arguments.title, amount: arguments.amount, isIncome: arguments.isIncome,
                category: arguments.category ?? (arguments.isIncome ? "Income" : "Uncategorized"),
                in: container.mainContext)
            activity.record("\(entry.isIncome ? "+" : "−")\(entry.amount.currency) \(entry.title)")
            return "Recorded \(entry.isIncome ? "income" : "expense") of \(entry.amount.currency) for \(entry.title)."
        }
    }
}

struct SuggestNextTool: Tool {
    let name = "suggestNext"
    let description = "Get the user's open items ranked by urgency. Use when they ask what to do next or are unsure."
    let container: ModelContainer

    @Generable
    struct Arguments {}

    func call(arguments: Arguments) async throws -> String {
        await MainActor.run {
            let ranked = NextUpEngine.rank(in: container.mainContext).prefix(4)
            guard !ranked.isEmpty else { return "Nothing is pending. The user is all caught up." }
            return ranked.enumerated()
                .map { "\($0.offset + 1). [\($0.element.section.title)] \($0.element.title): \($0.element.detail)" }
                .joined(separator: "\n")
        }
    }
}

struct OverviewTool: Tool {
    let name = "getOverview"
    let description = "Read the user's habits, upcoming assignments, budgets and bills."
    let container: ModelContainer

    @Generable
    struct Arguments {}

    func call(arguments: Arguments) async throws -> String {
        await MainActor.run {
            let context = container.mainContext
            let habits = (try? context.fetch(FetchDescriptor<Habit>())) ?? []
            let assignments = ((try? context.fetch(FetchDescriptor<Assignment>(sortBy: [SortDescriptor(\.dueDate)]))) ?? [])
                .filter { !$0.isCompleted }.prefix(5)
            let budgets = (try? context.fetch(FetchDescriptor<Budget>())) ?? []
            let entries = (try? context.fetch(FetchDescriptor<MoneyEntry>())) ?? []
            let bills = ((try? context.fetch(FetchDescriptor<Bill>(sortBy: [SortDescriptor(\.dueDate)]))) ?? [])
                .filter { !$0.isPaid }.prefix(3)

            var lines: [String] = []
            lines.append("Habits: " + habits.map { "\($0.name)\($0.isLoggedToday ? " (done today)" : "")\($0.isPriority ? " [priority]" : "")" }.joined(separator: ", "))
            lines.append("Assignments: " + assignments.map { "\($0.title) due \($0.dueDate.dueDescription), \(Int($0.progress * 100))%" }.joined(separator: "; "))
            lines.append("Budgets this month: " + budgets.map { "\($0.name) \(HubActions.spent(on: $0, entries: entries).currency) of \($0.limit.currency)" }.joined(separator: "; "))
            lines.append("Bills: " + bills.map { "\($0.name) \($0.amount.currency) \($0.dueDate.dueDescription)" }.joined(separator: "; "))
            return lines.joined(separator: "\n")
        }
    }
}
