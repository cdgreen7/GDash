import Foundation
import SwiftData

/// Every mutation the UI, the assistant, and Shortcuts perform goes through here so they behave identically.
@MainActor
enum HubActions {
    // MARK: Assignments

    @discardableResult
    static func addAssignment(title: String, course: String = "", due: Date, priority: Priority = .medium,
                              notes: String = "", in context: ModelContext) -> Assignment {
        let assignment = Assignment(title: title, course: course, dueDate: due, priority: priority, notes: notes)
        context.insert(assignment)
        save(context)
        return assignment
    }

    static func assignment(named name: String, in context: ModelContext) -> Assignment? {
        let all = (try? context.fetch(FetchDescriptor<Assignment>())) ?? []
        return bestMatch(name, in: all.filter { !$0.isCompleted }, key: \.title)
            ?? bestMatch(name, in: all, key: \.title)
    }

    // MARK: Schedule

    @discardableResult
    static func addEvent(title: String, start: Date, end: Date, allDay: Bool = false, kind: EventKind = .personal,
                         notes: String = "", in context: ModelContext) -> HubEvent {
        let event = HubEvent(title: title, start: start, end: end, isAllDay: allDay, kind: kind, notes: notes)
        context.insert(event)
        save(context)
        return event
    }

    // MARK: Habits

    @discardableResult
    static func addHabit(name: String, icon: String = "flame.fill", colorHex: String = "A3E635",
                         isPriority: Bool = false, in context: ModelContext) -> Habit {
        let habit = Habit(name: name, icon: icon, colorHex: colorHex, isPriority: isPriority)
        context.insert(habit)
        save(context)
        return habit
    }

    static func setHabit(_ habit: Habit, logged: Bool, on day: Date = .now, in context: ModelContext) {
        let existing = (habit.logs ?? []).filter { Calendar.current.isDate($0.date, inSameDayAs: day) }
        if logged {
            guard existing.isEmpty else { return }
            let log = HabitLog(date: day)
            context.insert(log)
            log.habit = habit
        } else {
            existing.forEach(context.delete)
        }
        save(context)
    }

    static func habit(named name: String, in context: ModelContext) -> Habit? {
        bestMatch(name, in: (try? context.fetch(FetchDescriptor<Habit>())) ?? [], key: \.name)
    }

    // MARK: Money

    @discardableResult
    static func addEntry(title: String, amount: Double, isIncome: Bool, category: String,
                         date: Date = .now, in context: ModelContext) -> MoneyEntry {
        let entry = MoneyEntry(title: title, amount: amount, isIncome: isIncome, category: category, date: date)
        context.insert(entry)
        save(context)
        return entry
    }

    /// Creates the budget, or updates the limit if one with that name exists.
    @discardableResult
    static func setBudget(category: String, limit: Double, in context: ModelContext) -> Budget {
        let budgets = (try? context.fetch(FetchDescriptor<Budget>())) ?? []
        if let existing = budgets.first(where: { $0.name.localizedCaseInsensitiveCompare(category) == .orderedSame }) {
            existing.limit = limit
            save(context)
            return existing
        }
        let color = Theme.palette[budgets.count % Theme.palette.count]
        let budget = Budget(name: category.capitalized, limit: limit, colorHex: color)
        context.insert(budget)
        save(context)
        return budget
    }

    @discardableResult
    static func addBill(name: String, amount: Double, due: Date, isCreditCard: Bool, repeatsMonthly: Bool,
                        in context: ModelContext) -> Bill {
        let bill = Bill(name: name, amount: amount, dueDate: due, isCreditCard: isCreditCard, repeatsMonthly: repeatsMonthly)
        context.insert(bill)
        save(context)
        return bill
    }

    /// Records the payment as an expense, then rolls a recurring bill to next month.
    static func pay(_ bill: Bill, in context: ModelContext) {
        addEntry(title: bill.name, amount: bill.amount, isIncome: false, category: "Bills", in: context)
        if bill.repeatsMonthly {
            bill.dueDate = Calendar.current.date(byAdding: .month, value: 1, to: bill.dueDate) ?? bill.dueDate
        } else {
            bill.isPaid = true
        }
        save(context)
    }

    static func spent(on budget: Budget, entries: [MoneyEntry], month: Date = .now) -> Double {
        entries
            .filter { !$0.isIncome && $0.category.localizedCaseInsensitiveCompare(budget.name) == .orderedSame }
            .filter { Calendar.current.isDate($0.date, equalTo: month, toGranularity: .month) }
            .reduce(0) { $0 + $1.amount }
    }

    // MARK: Helpers

    static func save(_ context: ModelContext) {
        try? context.save()
    }

    /// Exact match first, then prefix, then substring, all case-insensitive.
    private static func bestMatch<T>(_ query: String, in items: [T], key: KeyPath<T, String>) -> T? {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return nil }
        return items.first { $0[keyPath: key].lowercased() == q }
            ?? items.first { $0[keyPath: key].lowercased().hasPrefix(q) }
            ?? items.first { $0[keyPath: key].lowercased().contains(q) || q.contains($0[keyPath: key].lowercased()) }
    }
}
