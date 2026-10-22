import SwiftUI

enum Theme {
    static let background = Color(hex: "08080C")
    static let hairline = Color.white.opacity(0.09)
    static let secondary = Color.white.opacity(0.62)
    static let tertiary = Color.white.opacity(0.38)
    static let danger = Color(hex: "F87171")
    static let success = Color(hex: "34D399")
    static let corner: CGFloat = 26

    /// Swatches offered when creating habits and budgets.
    static let palette = ["A3E635", "22D3EE", "8B5CF6", "F472B6", "FBBF24", "F97316", "34D399", "60A5FA", "F87171"]
}

/// The top-level areas of the hub. Each one owns an accent gradient used throughout its screens.
enum HubSection: String, CaseIterable, Identifiable, Hashable {
    case assignments, calendar, habits, finances, assistant

    var id: String { rawValue }

    var title: String {
        switch self {
        case .assignments: "Assignments"
        case .calendar: "Schedule"
        case .habits: "Habits"
        case .finances: "Finances"
        case .assistant: "Assistant"
        }
    }

    var icon: String {
        switch self {
        case .assignments: "checklist"
        case .calendar: "calendar"
        case .habits: "flame.fill"
        case .finances: "chart.pie.fill"
        case .assistant: "sparkles"
        }
    }

    var colors: [Color] {
        switch self {
        case .assignments: [Color(hex: "8B5CF6"), Color(hex: "EC4899")]
        case .calendar: [Color(hex: "22D3EE"), Color(hex: "3B82F6")]
        case .habits: [Color(hex: "A3E635"), Color(hex: "10B981")]
        case .finances: [Color(hex: "FBBF24"), Color(hex: "F97316")]
        case .assistant: [Color(hex: "F472B6"), Color(hex: "A78BFA")]
        }
    }

    var tint: Color { colors[0] }

    var gradient: LinearGradient {
        LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

extension Color {
    init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var value: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&value)
        guard cleaned.count == 6 else {
            self.init(white: 1)
            return
        }
        self.init(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}

extension Font {
    static func display(_ size: CGFloat, weight: Font.Weight = .heavy) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }
}

extension Habit {
    var color: Color { Color(hex: colorHex) }
}

extension Budget {
    var color: Color { Color(hex: colorHex) }
}

extension EventKind {
    var color: Color {
        switch self {
        case .personal: Color(hex: "22D3EE")
        case .work: Color(hex: "60A5FA")
        case .school: Color(hex: "C084FC")
        case .habit: Color(hex: "A3E635")
        case .other: Color(hex: "94A3B8")
        }
    }
}

extension Priority {
    var color: Color {
        switch self {
        case .low: Color(hex: "94A3B8")
        case .medium: Color(hex: "FBBF24")
        case .high: Color(hex: "F87171")
        }
    }
}

extension Date {
    /// Compact, human phrasing for due dates: "Today, 5:00 PM", "Tomorrow", "Fri", "Oct 30".
    var dueDescription: String {
        let cal = Calendar.current
        let time = formatted(date: .omitted, time: .shortened)
        if self < .now {
            return "Overdue · " + formatted(.relative(presentation: .named))
        }
        if cal.isDateInToday(self) { return "Today, \(time)" }
        if cal.isDateInTomorrow(self) { return "Tomorrow, \(time)" }
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: .now), to: cal.startOfDay(for: self)).day ?? 0
        if days < 7 { return formatted(.dateTime.weekday(.wide)) + ", \(time)" }
        return formatted(.dateTime.month(.abbreviated).day())
    }

    var startOfDay: Date { Calendar.current.startOfDay(for: self) }
}

extension Double {
    var currency: String {
        formatted(.currency(code: Locale.current.currency?.identifier ?? "USD"))
    }
}
