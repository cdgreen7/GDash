import SwiftData
import SwiftUI

/// One sheet for everything that can land on the calendar.
struct AddScheduleItemSheet: View {
    enum Kind: String, CaseIterable, Identifiable {
        case event = "Event", assignment = "Assignment", bill = "Bill / Card", habit = "Habit check-in"
        var id: String { rawValue }

        var icon: String {
            switch self {
            case .event: "calendar"
            case .assignment: "doc.text.fill"
            case .bill: "creditcard.fill"
            case .habit: "flame.fill"
            }
        }

        var color: Color {
            switch self {
            case .event: HubSection.calendar.tint
            case .assignment: CalendarFeed.assignmentColor
            case .bill: CalendarFeed.billColor
            case .habit: HubSection.habits.tint
            }
        }
    }

    enum Repeat: String, CaseIterable, Identifiable {
        case never = "Never", daily = "Daily (2 weeks)", weekly = "Weekly (8 weeks)"
        var id: String { rawValue }
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \Habit.createdAt) private var habits: [Habit]

    @State private var kind: Kind
    @State private var title = ""
    @State private var start: Date
    @State private var end: Date
    @State private var allDay = false
    @State private var eventKind: EventKind = .personal
    @State private var repeatRule: Repeat = .never
    @State private var course = ""
    @State private var priority: Priority = .medium
    @State private var amount: Double?
    @State private var isCreditCard = true
    @State private var repeatsMonthly = true
    @State private var habitID: UUID?
    @State private var notes = ""

    init(date: Date, kind: Kind = .event) {
        let cal = Calendar.current
        let hour = cal.isDateInToday(date) ? min(cal.component(.hour, from: .now) + 1, 23) : 9
        let start = cal.date(bySettingHour: hour, minute: 0, second: 0, of: date) ?? date
        _kind = State(initialValue: kind)
        _start = State(initialValue: start)
        _end = State(initialValue: start.addingTimeInterval(3600))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(Kind.allCases) { option in
                                Label(option.rawValue, systemImage: option.icon)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(kind == option ? .black : .white)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 9)
                                    .background(kind == option ? option.color : Color.white.opacity(0.08), in: .capsule)
                                    .onTapGesture { withAnimation(.snappy) { kind = option } }
                            }
                        }
                    }
                    .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
                }
                .listRowBackground(Color.clear)

                switch kind {
                case .event: eventFields
                case .assignment: assignmentFields
                case .bill: billFields
                case .habit: habitFields
                }

                if kind == .event || kind == .habit {
                    Section {
                        Picker("Repeat", selection: $repeatRule) {
                            ForEach(Repeat.allCases) { Text($0.rawValue).tag($0) }
                        }
                        TextField("Notes", text: $notes, axis: .vertical).lineLimit(2...5)
                    }
                }
            }
            .navigationTitle("Add to schedule")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Add", action: save).disabled(!isValid) }
            }
            .onChange(of: start) { old, new in
                end = new.addingTimeInterval(max(end.timeIntervalSince(old), 900))
            }
            .onAppear { if habitID == nil { habitID = habits.first?.id } }
        }
    }

    @ViewBuilder private var eventFields: some View {
        Section {
            TextField("Title", text: $title).font(.headline)
            Picker("Category", selection: $eventKind) {
                ForEach(EventKind.allCases.filter { $0 != .habit }) { Label($0.label, systemImage: $0.icon).tag($0) }
            }
        }
        Section {
            Toggle("All day", isOn: $allDay)
            DatePicker("Starts", selection: $start, displayedComponents: allDay ? .date : [.date, .hourAndMinute])
            if !allDay {
                DatePicker("Ends", selection: $end, in: start..., displayedComponents: [.date, .hourAndMinute])
            }
        }
    }

    @ViewBuilder private var assignmentFields: some View {
        Section {
            TextField("Assignment", text: $title).font(.headline)
            TextField("Course or project", text: $course)
        }
        Section {
            DatePicker("Due", selection: $start)
            Picker("Priority", selection: $priority) {
                ForEach(Priority.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
        }
    }

    @ViewBuilder private var billFields: some View {
        Section {
            TextField("Name (e.g. Visa card)", text: $title).font(.headline)
            TextField("Amount", value: $amount, format: .currency(code: Locale.current.currency?.identifier ?? "USD"))
                .keyboardType(.decimalPad)
        }
        Section {
            DatePicker("Due", selection: $start, displayedComponents: .date)
            Toggle("Credit card", isOn: $isCreditCard)
            Toggle("Repeats monthly", isOn: $repeatsMonthly)
        }
    }

    @ViewBuilder private var habitFields: some View {
        Section {
            if habits.isEmpty {
                Text("Create a habit in the Habits tab first.").foregroundStyle(Theme.secondary)
            } else {
                Picker("Habit", selection: $habitID) {
                    ForEach(habits) { Label($0.name, systemImage: $0.icon).tag(Optional($0.id)) }
                }
            }
            DatePicker("Check-in", selection: $start)
        }
    }

    private var isValid: Bool {
        switch kind {
        case .habit: habitID != nil
        case .bill: !title.trimmingCharacters(in: .whitespaces).isEmpty && (amount ?? 0) > 0
        default: !title.trimmingCharacters(in: .whitespaces).isEmpty
        }
    }

    private func save() {
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        switch kind {
        case .event:
            let startDate = allDay ? start.startOfDay : start
            let endDate = allDay ? startDate.addingTimeInterval(86399) : end
            addRepeating(title: trimmed, start: startDate, end: endDate, kind: eventKind)
        case .assignment:
            HubActions.addAssignment(title: trimmed, course: course, due: start, priority: priority, in: context)
        case .bill:
            HubActions.addBill(name: trimmed, amount: amount ?? 0, due: start, isCreditCard: isCreditCard,
                               repeatsMonthly: repeatsMonthly, in: context)
        case .habit:
            guard let habit = habits.first(where: { $0.id == habitID }) else { return }
            addRepeating(title: "\(habit.name) check-in", start: start, end: start.addingTimeInterval(900), kind: .habit)
        }
        dismiss()
    }

    private func addRepeating(title: String, start: Date, end: Date, kind: EventKind) {
        let (count, component): (Int, Calendar.Component) = switch repeatRule {
        case .never: (1, .day)
        case .daily: (14, .day)
        case .weekly: (8, .weekOfYear)
        }
        let cal = Calendar.current
        for offset in 0..<count {
            guard let s = cal.date(byAdding: component, value: offset, to: start),
                  let e = cal.date(byAdding: component, value: offset, to: end) else { continue }
            HubActions.addEvent(title: title, start: s, end: e, allDay: allDay && kind != .habit, kind: kind, notes: notes, in: context)
        }
    }
}
