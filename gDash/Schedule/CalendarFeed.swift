import SwiftUI

/// A unified row for the schedule, built from events, assignment due dates and bills.
struct AgendaItem: Identifiable {
    enum Ref {
        case event(HubEvent)
        case assignment(Assignment)
        case bill(Bill)
    }

    let id: String
    let ref: Ref
    let title: String
    let subtitle: String
    let start: Date
    let end: Date?
    let isAllDay: Bool
    let color: Color
    let icon: String
    let isDone: Bool

    var isTimed: Bool { !isAllDay && end != nil }
}

enum CalendarFeed {
    static let assignmentColor = HubSection.assignments.colors[1]
    static let billColor = HubSection.finances.tint

    static func items(on day: Date, events: [HubEvent], assignments: [Assignment], bills: [Bill]) -> [AgendaItem] {
        let start = day.startOfDay
        let end = Calendar.current.date(byAdding: .day, value: 1, to: start)!
        return items(in: DateInterval(start: start, end: end), events: events, assignments: assignments, bills: bills)
            .sorted { lhs, rhs in
                if lhs.isAllDay != rhs.isAllDay { return lhs.isAllDay }
                return lhs.start < rhs.start
            }
    }

    static func items(in range: DateInterval, events: [HubEvent], assignments: [Assignment], bills: [Bill]) -> [AgendaItem] {
        var out: [AgendaItem] = []

        for event in events where event.start < range.end && event.end >= range.start {
            let time = event.isAllDay
                ? "All day"
                : "\(event.start.formatted(date: .omitted, time: .shortened)) – \(event.end.formatted(date: .omitted, time: .shortened))"
            out.append(AgendaItem(
                id: "e-\(event.id)", ref: .event(event), title: event.title, subtitle: time,
                start: event.start, end: event.end, isAllDay: event.isAllDay,
                color: event.kind.color, icon: event.kind.icon, isDone: false
            ))
        }

        for assignment in assignments where range.contains(assignment.dueDate) {
            let course = assignment.course.isEmpty ? "" : "\(assignment.course) · "
            out.append(AgendaItem(
                id: "a-\(assignment.id)", ref: .assignment(assignment), title: assignment.title,
                subtitle: "\(course)Due \(assignment.dueDate.formatted(date: .omitted, time: .shortened)) · \(Int(assignment.progress * 100))%",
                start: assignment.dueDate, end: nil, isAllDay: true,
                color: assignmentColor, icon: "doc.text.fill", isDone: assignment.isCompleted
            ))
        }

        for bill in bills {
            for (index, due) in occurrences(of: bill, in: range).enumerated() {
                out.append(AgendaItem(
                    id: "b-\(bill.id)-\(index)", ref: .bill(bill), title: bill.name,
                    subtitle: "\(bill.amount.currency) due\(bill.isCreditCard ? " · Card" : "")",
                    start: due, end: nil, isAllDay: true,
                    color: billColor, icon: bill.isCreditCard ? "creditcard.fill" : "dollarsign.circle.fill",
                    isDone: bill.isPaid
                ))
            }
        }
        return out
    }

    /// Recurring bills are projected forward so they show up in future months.
    static func occurrences(of bill: Bill, in range: DateInterval) -> [Date] {
        guard bill.repeatsMonthly, !bill.isPaid else {
            return range.contains(bill.dueDate) ? [bill.dueDate] : []
        }
        var dates: [Date] = []
        for offset in 0..<24 {
            guard let date = Calendar.current.date(byAdding: .month, value: offset, to: bill.dueDate) else { break }
            if date >= range.end { break }
            if date >= range.start { dates.append(date) }
        }
        return dates
    }

    /// Up to three marker colors per day, keyed by start of day.
    static func markers(in range: DateInterval, events: [HubEvent], assignments: [Assignment], bills: [Bill]) -> [Date: [Color]] {
        var result: [Date: [Color]] = [:]
        let cal = Calendar.current
        for item in items(in: range, events: events, assignments: assignments, bills: bills) {
            var day = max(item.start, range.start).startOfDay
            let last = min(item.end ?? item.start, range.end.addingTimeInterval(-1)).startOfDay
            while day <= last {
                if result[day, default: []].count < 3 { result[day, default: []].append(item.color) }
                day = cal.date(byAdding: .day, value: 1, to: day)!
            }
        }
        return result
    }
}
