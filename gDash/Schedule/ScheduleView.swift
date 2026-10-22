import SwiftData
import SwiftUI

struct ScheduleView: View {
    enum Mode: String, CaseIterable, Identifiable {
        case today = "Today", day = "Day", month = "Month", year = "Year"
        var id: String { rawValue }
    }

    @Environment(\.modelContext) private var context
    @Query(sort: \HubEvent.start) private var events: [HubEvent]
    @Query(sort: \Assignment.dueDate) private var assignments: [Assignment]
    @Query(sort: \Bill.dueDate) private var bills: [Bill]
    @Query(sort: \Habit.createdAt) private var habits: [Habit]

    @AppStorage("schedule.mode") private var mode: Mode = .today
    @State private var selected = Date.now
    @State private var showingAdd = false
    @State private var editingAssignment: Assignment?

    var body: some View {
        VStack(spacing: 12) {
            Picker("View", selection: $mode.animation(.snappy)) {
                ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 18)

            switch mode {
            case .today:
                TodayAgenda(events: events, assignments: assignments, bills: bills, habits: habits, actions: actions)
            case .day:
                DayTimeline(date: $selected,
                            items: CalendarFeed.items(on: selected, events: events, assignments: assignments, bills: bills),
                            actions: actions)
            case .month:
                ScrollView {
                    VStack(spacing: 16) {
                        MonthGrid(selected: $selected, markers: markers(for: .month))
                        AgendaSection(title: selected.formatted(.dateTime.weekday(.wide).month().day()),
                                      items: CalendarFeed.items(on: selected, events: events, assignments: assignments, bills: bills),
                                      actions: actions)
                    }
                    .padding(.horizontal, 18)
                    .padding(.bottom, 40)
                }
            case .year:
                YearGrid(selected: $selected, markers: markers(for: .year)) { month in
                    selected = month
                    withAnimation(.snappy) { mode = .month }
                }
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(HubBackground(accent: HubSection.calendar.tint))
        .navigationTitle("Schedule")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Today") { withAnimation { selected = .now } }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Add", systemImage: "plus") { showingAdd = true }
            }
        }
        .sheet(isPresented: $showingAdd) { AddScheduleItemSheet(date: selected) }
        .sheet(item: $editingAssignment) { AssignmentEditor(assignment: $0) }
    }

    private func markers(for component: Calendar.Component) -> [Date: [Color]] {
        guard let range = Calendar.current.dateInterval(of: component, for: selected) else { return [:] }
        return CalendarFeed.markers(in: range, events: events, assignments: assignments, bills: bills)
    }

    private var actions: AgendaActions {
        AgendaActions(
            toggle: { item in
                switch item.ref {
                case .assignment(let assignment): assignment.toggleComplete()
                case .bill(let bill): if !bill.isPaid { HubActions.pay(bill, in: context) }
                case .event: break
                }
                HubActions.save(context)
            },
            open: { item in
                if case .assignment(let assignment) = item.ref { editingAssignment = assignment }
            },
            delete: { item in
                switch item.ref {
                case .event(let event): context.delete(event)
                case .assignment(let assignment): context.delete(assignment)
                case .bill(let bill): context.delete(bill)
                }
                HubActions.save(context)
            }
        )
    }
}

struct AgendaActions {
    var toggle: (AgendaItem) -> Void
    var open: (AgendaItem) -> Void
    var delete: (AgendaItem) -> Void
}

// MARK: - Today list

private struct TodayAgenda: View {
    @Environment(\.modelContext) private var context
    let events: [HubEvent]
    let assignments: [Assignment]
    let bills: [Bill]
    let habits: [Habit]
    let actions: AgendaActions

    var body: some View {
        let today = CalendarFeed.items(on: .now, events: events, assignments: assignments, bills: bills)
        let overdue = assignments.filter(\.isOverdue).filter { !Calendar.current.isDateInToday($0.dueDate) }
        let pendingHabits = habits.filter { !$0.isLoggedToday }.sorted { $0.isPriority && !$1.isPriority }
        let weekRange = DateInterval(start: Calendar.current.date(byAdding: .day, value: 1, to: .now.startOfDay)!,
                                     duration: 6 * 86400)
        let upcoming = CalendarFeed.items(in: weekRange, events: events, assignments: assignments, bills: bills)
            .filter { !$0.isDone }
            .sorted { $0.start < $1.start }

        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .lastTextBaseline) {
                    Text(Date.now.formatted(.dateTime.weekday(.wide)))
                        .font(.display(34))
                    Spacer()
                    Text("\(today.filter { !$0.isDone }.count + pendingHabits.count) to do")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.secondary)
                }

                if !overdue.isEmpty {
                    AgendaSection(title: "Overdue",
                                  items: CalendarFeed.items(in: DateInterval(start: .distantPast, end: .now.startOfDay),
                                                            events: [], assignments: overdue, bills: []),
                                  actions: actions)
                }

                AgendaSection(title: "Today", items: today, actions: actions)

                if !pendingHabits.isEmpty {
                    SectionTitle(title: "Habits to check in")
                    ForEach(pendingHabits) { habit in
                        GlassCard(padding: 14) {
                            HStack(spacing: 12) {
                                IconBadge(systemName: habit.icon, colors: [habit.color, habit.color.opacity(0.6)], size: 34)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(habit.name).font(.subheadline.weight(.semibold))
                                    if habit.currentStreak > 0 {
                                        Text("\(habit.currentStreak)-day streak").font(.caption).foregroundStyle(Theme.secondary)
                                    }
                                }
                                Spacer()
                                if habit.isPriority {
                                    Image(systemName: "star.fill").foregroundStyle(HubSection.finances.tint)
                                }
                                Button("Log") {
                                    withAnimation { HubActions.setHabit(habit, logged: true, in: context) }
                                }
                                .buttonStyle(.glassProminent)
                                .tint(habit.color)
                            }
                        }
                    }
                }

                if !upcoming.isEmpty {
                    SectionTitle(title: "Next 7 days")
                    ForEach(upcoming) { item in
                        AgendaRow(item: item, showDate: true, actions: actions)
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 40)
        }
    }
}

struct AgendaSection: View {
    let title: String
    let items: [AgendaItem]
    let actions: AgendaActions

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle(title: title, trailing: items.isEmpty ? nil : "\(items.count)")
            if items.isEmpty {
                Text("Nothing scheduled.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.tertiary)
                    .padding(.vertical, 6)
            }
            ForEach(items) { AgendaRow(item: $0, showDate: false, actions: actions) }
        }
    }
}

struct AgendaRow: View {
    let item: AgendaItem
    let showDate: Bool
    let actions: AgendaActions

    var body: some View {
        GlassCard(padding: 14) {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(item.color)
                    .frame(width: 5)
                    .frame(maxHeight: .infinity)
                Image(systemName: item.icon)
                    .foregroundStyle(item.color)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.title)
                        .font(.subheadline.weight(.semibold))
                        .strikethrough(item.isDone)
                        .foregroundStyle(item.isDone ? Theme.secondary : .white)
                    Text(showDate ? "\(item.start.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())) · \(item.subtitle)" : item.subtitle)
                        .font(.caption)
                        .foregroundStyle(Theme.secondary)
                        .lineLimit(1)
                }
                Spacer()
                switch item.ref {
                case .assignment, .bill:
                    Button { withAnimation { actions.toggle(item) } } label: {
                        Image(systemName: item.isDone ? "checkmark.circle.fill" : "circle")
                            .font(.title3)
                            .foregroundStyle(item.isDone ? Theme.success : Theme.tertiary)
                    }
                    .buttonStyle(.borderless)
                case .event:
                    EmptyView()
                }
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .contentShape(.rect)
        .onTapGesture { actions.open(item) }
        .contextMenu {
            switch item.ref {
            case .assignment(let a):
                Button(a.isCompleted ? "Reopen" : "Mark complete", systemImage: "checkmark") { actions.toggle(item) }
                Button("Edit", systemImage: "pencil") { actions.open(item) }
            case .bill(let b) where !b.isPaid:
                Button("Mark paid", systemImage: "dollarsign.circle") { actions.toggle(item) }
            default:
                EmptyView()
            }
            Button("Delete", systemImage: "trash", role: .destructive) { actions.delete(item) }
        }
    }
}

// MARK: - Month

struct MonthGrid: View {
    @Binding var selected: Date
    let markers: [Date: [Color]]

    private let cal = Calendar.current

    var body: some View {
        GlassCard(tint: HubSection.calendar.tint) {
            VStack(spacing: 14) {
                HStack {
                    Text(selected.formatted(.dateTime.month(.wide).year()))
                        .font(.display(24))
                    Spacer()
                    stepButton("chevron.left", -1)
                    stepButton("chevron.right", 1)
                }

                HStack {
                    ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                        Text(symbol).font(.caption.weight(.bold)).foregroundStyle(Theme.tertiary).frame(maxWidth: .infinity)
                    }
                }

                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 7), spacing: 6) {
                    ForEach(Array(monthDays(for: selected).enumerated()), id: \.offset) { _, day in
                        if let day {
                            dayCell(day)
                        } else {
                            Color.clear.frame(height: 44)
                        }
                    }
                }
            }
        }
        .gesture(DragGesture(minimumDistance: 30).onEnded { value in
            if abs(value.translation.width) > abs(value.translation.height) {
                step(value.translation.width < 0 ? 1 : -1)
            }
        })
    }

    private func dayCell(_ day: Date) -> some View {
        let isSelected = cal.isDate(day, inSameDayAs: selected)
        let isToday = cal.isDateInToday(day)
        return VStack(spacing: 4) {
            Text(day.formatted(.dateTime.day()))
                .font(.system(size: 15, weight: isSelected || isToday ? .bold : .medium, design: .rounded))
                .foregroundStyle(isSelected ? .black : .white)
                .frame(width: 34, height: 34)
                .background {
                    if isSelected {
                        Circle().fill(HubSection.calendar.gradient)
                    } else if isToday {
                        Circle().stroke(HubSection.calendar.tint, lineWidth: 1.5)
                    }
                }
            HStack(spacing: 3) {
                ForEach(Array((markers[day.startOfDay] ?? []).enumerated()), id: \.offset) { _, color in
                    Circle().fill(color).frame(width: 5, height: 5)
                }
            }
            .frame(height: 5)
        }
        .frame(height: 44)
        .contentShape(.rect)
        .onTapGesture { withAnimation(.snappy) { selected = day } }
    }

    private func stepButton(_ icon: String, _ delta: Int) -> some View {
        Button { step(delta) } label: {
            Image(systemName: icon).font(.headline).frame(width: 36, height: 36)
        }
        .glassEffect(.regular.interactive(), in: .circle)
    }

    private func step(_ delta: Int) {
        withAnimation(.snappy) {
            selected = cal.date(byAdding: .month, value: delta, to: selected) ?? selected
        }
    }

    private var weekdaySymbols: [String] {
        let symbols = cal.veryShortStandaloneWeekdaySymbols
        let first = cal.firstWeekday - 1
        return Array(symbols[first...] + symbols[..<first])
    }
}

func monthDays(for date: Date) -> [Date?] {
    let cal = Calendar.current
    guard let first = cal.dateInterval(of: .month, for: date)?.start,
          let count = cal.range(of: .day, in: .month, for: date)?.count else { return [] }
    let offset = (cal.component(.weekday, from: first) - cal.firstWeekday + 7) % 7
    return Array(repeating: nil, count: offset) + (0..<count).map { cal.date(byAdding: .day, value: $0, to: first) }
}

// MARK: - Year

private struct YearGrid: View {
    @Binding var selected: Date
    let markers: [Date: [Color]]
    let openMonth: (Date) -> Void

    private let cal = Calendar.current

    var body: some View {
        let year = cal.dateInterval(of: .year, for: selected)!.start
        ScrollView {
            VStack(spacing: 16) {
                HStack {
                    Text(selected.formatted(.dateTime.year()))
                        .font(.display(34))
                    Spacer()
                    Button { shift(-1) } label: { Image(systemName: "chevron.left").frame(width: 36, height: 36) }
                        .glassEffect(.regular.interactive(), in: .circle)
                    Button { shift(1) } label: { Image(systemName: "chevron.right").frame(width: 36, height: 36) }
                        .glassEffect(.regular.interactive(), in: .circle)
                }

                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), spacing: 12) {
                    ForEach(0..<12, id: \.self) { index in
                        let month = cal.date(byAdding: .month, value: index, to: year)!
                        miniMonth(month)
                            .onTapGesture { openMonth(month) }
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 40)
        }
    }

    private func miniMonth(_ month: Date) -> some View {
        let isCurrent = cal.isDate(month, equalTo: .now, toGranularity: .month)
        return GlassCard(tint: isCurrent ? HubSection.calendar.tint : nil, padding: 10) {
            VStack(alignment: .leading, spacing: 6) {
                Text(month.formatted(.dateTime.month(.abbreviated)))
                    .font(.system(size: 14, weight: .heavy, design: .rounded))
                    .foregroundStyle(isCurrent ? HubSection.calendar.tint : .white)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7), spacing: 2) {
                    ForEach(Array(monthDays(for: month).enumerated()), id: \.offset) { _, day in
                        if let day {
                            let color = markers[day.startOfDay]?.first
                            Text(day.formatted(.dateTime.day()))
                                .font(.system(size: 7.5, weight: color == nil ? .regular : .heavy))
                                .foregroundStyle(cal.isDateInToday(day) ? .black : color ?? Theme.secondary)
                                .frame(width: 11, height: 11)
                                .background(cal.isDateInToday(day) ? Circle().fill(HubSection.calendar.tint) : nil)
                        } else {
                            Color.clear.frame(width: 11, height: 11)
                        }
                    }
                }
            }
        }
    }

    private func shift(_ years: Int) {
        withAnimation(.snappy) { selected = cal.date(byAdding: .year, value: years, to: selected) ?? selected }
    }
}

// MARK: - Day

private struct DayTimeline: View {
    @Binding var date: Date
    let items: [AgendaItem]
    let actions: AgendaActions

    private let hourHeight: CGFloat = 60
    private let gutter: CGFloat = 52

    private struct Placed {
        let item: AgendaItem
        let y: CGFloat
        let height: CGFloat
        let column: Int
        var columns: Int
    }

    var body: some View {
        let allDay = items.filter { !$0.isTimed }
        let placed = layout(items.filter(\.isTimed))

        VStack(spacing: 12) {
            HStack {
                VStack(alignment: .leading) {
                    Text(date.formatted(.dateTime.weekday(.wide))).font(.display(30))
                    Text(date.formatted(.dateTime.month(.wide).day().year()))
                        .font(.subheadline).foregroundStyle(Theme.secondary)
                }
                Spacer()
                ForEach([-1, 1], id: \.self) { delta in
                    Button {
                        withAnimation(.snappy) { date = Calendar.current.date(byAdding: .day, value: delta, to: date)! }
                    } label: {
                        Image(systemName: delta < 0 ? "chevron.left" : "chevron.right").frame(width: 36, height: 36)
                    }
                    .glassEffect(.regular.interactive(), in: .circle)
                }
            }
            .padding(.horizontal, 18)

            if !allDay.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(allDay) { item in
                            Label(item.title, systemImage: item.icon)
                                .font(.caption.weight(.semibold))
                                .strikethrough(item.isDone)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(item.color.opacity(0.22), in: .capsule)
                                .overlay(Capsule().stroke(item.color.opacity(0.5)))
                                .onTapGesture { actions.open(item) }
                        }
                    }
                    .padding(.horizontal, 18)
                }
            }

            ScrollViewReader { proxy in
                ScrollView {
                    ZStack(alignment: .topLeading) {
                        VStack(spacing: 0) {
                            ForEach(0..<24, id: \.self) { hour in
                                HStack(alignment: .top, spacing: 8) {
                                    Text(hourLabel(hour))
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(Theme.tertiary)
                                        .frame(width: gutter - 8, alignment: .trailing)
                                        .offset(y: -6)
                                    Rectangle().fill(Theme.hairline).frame(height: 1)
                                }
                                .frame(height: hourHeight, alignment: .top)
                                .id(hour)
                            }
                        }

                        GeometryReader { geo in
                            let columnArea = geo.size.width - gutter
                            ForEach(placed, id: \.item.id) { slot in
                                let width = columnArea / CGFloat(slot.columns)
                                eventBlock(slot.item)
                                    .frame(width: width - 4, height: max(slot.height - 2, 28))
                                    .offset(x: gutter + CGFloat(slot.column) * width, y: slot.y)
                            }

                            if Calendar.current.isDateInToday(date) {
                                let minutes = Date.now.timeIntervalSince(date.startOfDay) / 60
                                HStack(spacing: 0) {
                                    Circle().fill(Theme.danger).frame(width: 8, height: 8)
                                    Rectangle().fill(Theme.danger).frame(height: 1.5)
                                }
                                .offset(x: gutter - 4, y: CGFloat(minutes / 60) * hourHeight - 4)
                            }
                        }
                    }
                    .frame(height: hourHeight * 24)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 40)
                }
                .onAppear {
                    let hour = Calendar.current.component(.hour, from: placed.first?.item.start ?? .now)
                    proxy.scrollTo(max(hour - 1, 0), anchor: .top)
                }
            }
        }
    }

    private func eventBlock(_ item: AgendaItem) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(item.title).font(.caption.weight(.bold)).lineLimit(2)
            Text(item.subtitle).font(.caption2).foregroundStyle(.white.opacity(0.7)).lineLimit(1)
        }
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(item.color.opacity(0.28), in: .rect(cornerRadius: 10))
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 2).fill(item.color).frame(width: 3).padding(.vertical, 6)
        }
        .contextMenu {
            Button("Delete", systemImage: "trash", role: .destructive) { actions.delete(item) }
        }
    }

    /// Greedy column packing: overlapping events share the width of their cluster.
    private func layout(_ items: [AgendaItem]) -> [Placed] {
        let dayStart = date.startOfDay
        let dayEnd = dayStart.addingTimeInterval(86400)
        var placed: [Placed] = []
        var cluster: [Int] = []
        var columnEnds: [Date] = []
        var clusterEnd = Date.distantPast

        func closeCluster() {
            for index in cluster { placed[index].columns = max(columnEnds.count, 1) }
            cluster = []
            columnEnds = []
        }

        for item in items.sorted(by: { $0.start < $1.start }) {
            let start = max(item.start, dayStart)
            let end = min(item.end ?? start, dayEnd)
            if start >= clusterEnd { closeCluster() }
            let column = columnEnds.firstIndex { $0 <= start } ?? columnEnds.count
            if column == columnEnds.count { columnEnds.append(end) } else { columnEnds[column] = end }
            clusterEnd = max(clusterEnd, end)
            placed.append(Placed(item: item,
                                 y: CGFloat(start.timeIntervalSince(dayStart) / 3600) * hourHeight,
                                 height: CGFloat(end.timeIntervalSince(start) / 3600) * hourHeight,
                                 column: column, columns: 1))
            cluster.append(placed.count - 1)
        }
        closeCluster()
        return placed
    }

    private func hourLabel(_ hour: Int) -> String {
        let date = Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: .now)!
        return date.formatted(.dateTime.hour())
    }
}
