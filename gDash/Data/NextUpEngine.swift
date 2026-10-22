import Foundation
import SwiftData

struct Suggestion: Identifiable {
    let id = UUID()
    let title: String
    let detail: String
    let section: HubSection
    let score: Double
}

/// Ranks everything open across the hub by urgency so the home screen, assistant and
/// Shortcuts can answer "what should I do next?".
enum NextUpEngine {
    static func rank(assignments: [Assignment], habits: [Habit], bills: [Bill], events: [HubEvent],
                     now: Date = .now) -> [Suggestion] {
        var out: [Suggestion] = []
        let hour = Calendar.current.component(.hour, from: now)

        for event in events where !event.isAllDay && event.start > now {
            let minutes = event.start.timeIntervalSince(now) / 60
            guard minutes <= 180 else { continue }
            out.append(Suggestion(
                title: "Get ready for \(event.title)",
                detail: "Starts \(event.start.formatted(.relative(presentation: .named)))",
                section: .calendar,
                score: 40 - minutes / 6
            ))
        }

        for assignment in assignments where !assignment.isCompleted {
            let hoursLeft = assignment.dueDate.timeIntervalSince(now) / 3600
            let remaining = 1 - assignment.progress
            let weight = Double(assignment.priority.rawValue + 2)
            var score = weight * remaining * (48 / max(hoursLeft, 2))
            if hoursLeft < 0 { score += 50 }
            let percent = Int(assignment.progress * 100)
            out.append(Suggestion(
                title: assignment.title,
                detail: "\(assignment.dueDate.dueDescription) · \(percent)% done",
                section: .assignments,
                score: score
            ))
        }

        for habit in habits where !habit.isLoggedToday {
            let streak = habit.currentStreak
            var score = habit.isPriority ? 9.0 : 4.0
            score += min(Double(streak), 30) * 0.3
            if hour >= 18 { score += 4 }
            out.append(Suggestion(
                title: habit.name,
                detail: streak > 0 ? "Keep your \(streak)-day streak alive" : "Not logged today",
                section: .habits,
                score: score
            ))
        }

        for bill in bills where !bill.isPaid {
            let days = bill.dueDate.timeIntervalSince(now) / 86400
            let score: Double = days < 0 ? 45 : days <= 3 ? 16 : days <= 7 ? 6 : 0
            guard score > 0 else { continue }
            out.append(Suggestion(
                title: "Pay \(bill.name)",
                detail: "\(bill.amount.currency) · \(bill.dueDate.dueDescription)",
                section: .finances,
                score: score
            ))
        }

        return out.sorted { $0.score > $1.score }
    }

    @MainActor
    static func rank(in context: ModelContext) -> [Suggestion] {
        rank(
            assignments: (try? context.fetch(FetchDescriptor<Assignment>())) ?? [],
            habits: (try? context.fetch(FetchDescriptor<Habit>())) ?? [],
            bills: (try? context.fetch(FetchDescriptor<Bill>())) ?? [],
            events: (try? context.fetch(FetchDescriptor<HubEvent>())) ?? []
        )
    }
}
