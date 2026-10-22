import Foundation
import SwiftData

// All stored properties have defaults and relationships are optional so the schema stays
// compatible with CloudKit sync.

enum Priority: Int, CaseIterable, Identifiable {
    case low, medium, high

    var id: Int { rawValue }
    var label: String {
        switch self {
        case .low: "Low"
        case .medium: "Medium"
        case .high: "High"
        }
    }
}

@Model
final class Assignment {
    var id: UUID = UUID()
    var title: String = ""
    var course: String = ""
    var notes: String = ""
    var dueDate: Date = Date()
    var progress: Double = 0
    var isCompleted: Bool = false
    var completedAt: Date?
    var priorityRaw: Int = Priority.medium.rawValue
    var createdAt: Date = Date()

    init(title: String, course: String = "", dueDate: Date, priority: Priority = .medium, notes: String = "") {
        self.title = title
        self.course = course
        self.dueDate = dueDate
        self.priorityRaw = priority.rawValue
        self.notes = notes
    }

    var priority: Priority {
        get { Priority(rawValue: priorityRaw) ?? .medium }
        set { priorityRaw = newValue.rawValue }
    }

    var isOverdue: Bool { !isCompleted && dueDate < .now }

    func setProgress(_ value: Double) {
        progress = min(max(value, 0), 1)
        isCompleted = progress >= 1
        completedAt = isCompleted ? (completedAt ?? .now) : nil
    }

    func toggleComplete() {
        if isCompleted {
            setProgress(min(progress, 0.9))
        } else {
            setProgress(1)
        }
    }
}

enum EventKind: String, CaseIterable, Identifiable {
    case personal, work, school, habit, other

    var id: String { rawValue }
    var label: String { rawValue.capitalized }
    var icon: String {
        switch self {
        case .personal: "person.fill"
        case .work: "briefcase.fill"
        case .school: "graduationcap.fill"
        case .habit: "flame.fill"
        case .other: "circle.grid.2x2.fill"
        }
    }
}

/// A user-created calendar entry (appointments, classes, habit check-ins, etc.).
/// Assignment and bill due dates come from their own models and are merged in by `CalendarFeed`.
@Model
final class HubEvent {
    var id: UUID = UUID()
    var title: String = ""
    var notes: String = ""
    var start: Date = Date()
    var end: Date = Date()
    var isAllDay: Bool = false
    var kindRaw: String = EventKind.personal.rawValue

    init(title: String, start: Date, end: Date, isAllDay: Bool = false, kind: EventKind = .personal, notes: String = "") {
        self.title = title
        self.start = start
        self.end = max(end, start)
        self.isAllDay = isAllDay
        self.kindRaw = kind.rawValue
        self.notes = notes
    }

    var kind: EventKind {
        get { EventKind(rawValue: kindRaw) ?? .other }
        set { kindRaw = newValue.rawValue }
    }
}

@Model
final class Habit {
    var id: UUID = UUID()
    var name: String = ""
    var icon: String = "flame.fill"
    var colorHex: String = "A3E635"
    var isPriority: Bool = false
    var createdAt: Date = Date()
    @Relationship(deleteRule: .cascade, inverse: \HabitLog.habit)
    var logs: [HabitLog]? = []

    init(name: String, icon: String = "flame.fill", colorHex: String = "A3E635", isPriority: Bool = false) {
        self.name = name
        self.icon = icon
        self.colorHex = colorHex
        self.isPriority = isPriority
    }
}

@Model
final class HabitLog {
    var date: Date = Date()
    var habit: Habit?

    init(date: Date) {
        self.date = date
    }
}

extension Habit {
    var loggedDays: Set<Date> {
        Set((logs ?? []).map { $0.date.startOfDay })
    }

    func isLogged(on day: Date) -> Bool {
        loggedDays.contains(day.startOfDay)
    }

    var isLoggedToday: Bool { isLogged(on: .now) }

    /// Consecutive days logged ending today, or ending yesterday if today isn't logged yet
    /// (the streak isn't broken until the day is over).
    var currentStreak: Int {
        let days = loggedDays
        let cal = Calendar.current
        var cursor = Date.now.startOfDay
        if !days.contains(cursor) {
            cursor = cal.date(byAdding: .day, value: -1, to: cursor)!
        }
        var count = 0
        while days.contains(cursor) {
            count += 1
            cursor = cal.date(byAdding: .day, value: -1, to: cursor)!
        }
        return count
    }

    var bestStreak: Int {
        let cal = Calendar.current
        var best = 0
        var run = 0
        var previous: Date?
        for day in loggedDays.sorted() {
            if let previous, cal.date(byAdding: .day, value: 1, to: previous) == day {
                run += 1
            } else {
                run = 1
            }
            best = max(best, run)
            previous = day
        }
        return best
    }
}

@Model
final class Budget {
    var id: UUID = UUID()
    var name: String = ""
    var limit: Double = 0
    var icon: String = "cart.fill"
    var colorHex: String = "FBBF24"
    var createdAt: Date = Date()

    init(name: String, limit: Double, icon: String = "cart.fill", colorHex: String = "FBBF24") {
        self.name = name
        self.limit = limit
        self.icon = icon
        self.colorHex = colorHex
    }
}

/// A single income or expense. `category` matches a `Budget.name` for expenses.
@Model
final class MoneyEntry {
    var id: UUID = UUID()
    var title: String = ""
    var amount: Double = 0
    var isIncome: Bool = false
    var category: String = ""
    var date: Date = Date()

    init(title: String, amount: Double, isIncome: Bool, category: String, date: Date = .now) {
        self.title = title
        self.amount = abs(amount)
        self.isIncome = isIncome
        self.category = category
        self.date = date
    }
}

@Model
final class Bill {
    var id: UUID = UUID()
    var name: String = ""
    var amount: Double = 0
    var dueDate: Date = Date()
    var isCreditCard: Bool = false
    var isPaid: Bool = false
    var repeatsMonthly: Bool = true
    var createdAt: Date = Date()

    init(name: String, amount: Double, dueDate: Date, isCreditCard: Bool = false, repeatsMonthly: Bool = true) {
        self.name = name
        self.amount = amount
        self.dueDate = dueDate
        self.isCreditCard = isCreditCard
        self.repeatsMonthly = repeatsMonthly
    }
}
