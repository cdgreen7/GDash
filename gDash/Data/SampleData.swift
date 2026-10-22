#if DEBUG
import Foundation
import SwiftData

/// Fills an empty hub with realistic data so every screen has something to show.
@MainActor
enum SampleData {
    static func load(into context: ModelContext) {
        let cal = Calendar.current
        func day(_ offset: Int, _ hour: Int = 23, _ minute: Int = 59) -> Date {
            let base = cal.date(byAdding: .day, value: offset, to: .now)!
            return cal.date(bySettingHour: hour, minute: minute, second: 0, of: base)!
        }

        let a1 = HubActions.addAssignment(title: "Lab report: Titration", course: "Chemistry", due: day(1, 17), priority: .high, in: context)
        a1.setProgress(0.6)
        let a2 = HubActions.addAssignment(title: "Essay draft", course: "English", due: day(3), in: context)
        a2.setProgress(0.25)
        HubActions.addAssignment(title: "Problem set 7", course: "Calculus", due: day(5, 9), priority: .high, in: context)
        HubActions.addAssignment(title: "Read chapters 4–5", course: "History", due: day(8), priority: .low, in: context)

        HubActions.addEvent(title: "Study group", start: day(0, 18, 0), end: day(0, 19, 30), kind: .school, in: context)
        HubActions.addEvent(title: "Dentist", start: day(2, 10, 0), end: day(2, 11, 0), in: context)
        HubActions.addEvent(title: "Shift at work", start: day(4, 13, 0), end: day(4, 18, 0), kind: .work, in: context)

        let habits = [
            HubActions.addHabit(name: "Workout", icon: "dumbbell.fill", colorHex: "A3E635", isPriority: true, in: context),
            HubActions.addHabit(name: "Read 20 min", icon: "book.fill", colorHex: "22D3EE", in: context),
            HubActions.addHabit(name: "Drink water", icon: "drop.fill", colorHex: "60A5FA", in: context),
            HubActions.addHabit(name: "Meditate", icon: "brain.head.profile", colorHex: "F472B6", isPriority: true, in: context),
        ]
        for (index, habit) in habits.enumerated() {
            for offset in 1...(4 + index * 3) where offset % (index + 3) != 0 {
                HubActions.setHabit(habit, logged: true, on: day(-offset, 9), in: context)
            }
        }
        HubActions.setHabit(habits[2], logged: true, in: context)

        HubActions.setBudget(category: "Groceries", limit: 300, in: context)
        HubActions.setBudget(category: "Dining", limit: 150, in: context)
        HubActions.setBudget(category: "Transport", limit: 100, in: context)
        HubActions.setBudget(category: "Fun", limit: 120, in: context)

        HubActions.addEntry(title: "Paycheck", amount: 1450, isIncome: true, category: "Job", date: day(-10, 9), in: context)
        HubActions.addEntry(title: "Tutoring", amount: 220, isIncome: true, category: "Side gigs", date: day(-4, 9), in: context)
        HubActions.addEntry(title: "Trader Joe's", amount: 86.40, isIncome: false, category: "Groceries", date: day(-3, 12), in: context)
        HubActions.addEntry(title: "Tacos", amount: 18.75, isIncome: false, category: "Dining", date: day(-2, 19), in: context)
        HubActions.addEntry(title: "Gas", amount: 42, isIncome: false, category: "Transport", date: day(-5, 8), in: context)
        HubActions.addEntry(title: "Movie night", amount: 31, isIncome: false, category: "Fun", date: day(-1, 21), in: context)
        HubActions.addEntry(title: "Rent share", amount: 650, isIncome: false, category: "Rent", date: day(-9, 9), in: context)

        HubActions.addBill(name: "Visa card", amount: 240, due: day(3), isCreditCard: true, repeatsMonthly: true, in: context)
        HubActions.addBill(name: "Phone", amount: 45, due: day(9), isCreditCard: false, repeatsMonthly: true, in: context)
        HubActions.addBill(name: "Spotify", amount: 11.99, due: day(14), isCreditCard: false, repeatsMonthly: true, in: context)
    }
}
#endif
