import SwiftData
import SwiftUI

struct HabitsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Habit.createdAt) private var habits: [Habit]
    @State private var showingNew = false
    @State private var detail: Habit?

    private var sorted: [Habit] {
        habits.sorted { lhs, rhs in
            if lhs.isPriority != rhs.isPriority { return lhs.isPriority }
            if lhs.isLoggedToday != rhs.isLoggedToday { return !lhs.isLoggedToday }
            return lhs.createdAt < rhs.createdAt
        }
    }

    var body: some View {
        List {
            summary
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)

            if habits.isEmpty {
                EmptyHint(icon: "flame", title: "No habits yet", message: "Tap + to start your first streak.")
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }

            ForEach(sorted) { habit in
                HabitRow(habit: habit)
                    .contentShape(.rect)
                    .onTapGesture { detail = habit }
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 6, leading: 18, bottom: 6, trailing: 18))
                    .swipeActions {
                        Button(role: .destructive) {
                            context.delete(habit)
                            HubActions.save(context)
                            GDashShortcuts.updateAppShortcutParameters()
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(HubBackground(accent: HubSection.habits.tint))
        .navigationTitle("Habits")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Add", systemImage: "plus") { showingNew = true }
            }
        }
        .sheet(isPresented: $showingNew) { HabitEditor(habit: nil) }
        .sheet(item: $detail) { HabitDetail(habit: $0) }
    }

    private var summary: some View {
        let done = habits.filter(\.isLoggedToday).count
        let bestActive = habits.map(\.currentStreak).max() ?? 0

        return GlassCard(tint: HubSection.habits.tint) {
            HStack(spacing: 18) {
                ZStack {
                    ProgressRing(value: habits.isEmpty ? 0 : Double(done) / Double(habits.count),
                                 colors: HubSection.habits.colors, lineWidth: 10)
                    Text("\(done)/\(habits.count)").font(.display(18, weight: .bold))
                }
                .frame(width: 78, height: 78)
                VStack(alignment: .leading, spacing: 4) {
                    Text(done == habits.count && !habits.isEmpty ? "All done today" : "\(habits.count - done) left today")
                        .font(.display(24))
                    Label("Longest active streak: \(bestActive) days", systemImage: "flame.fill")
                        .font(.subheadline)
                        .foregroundStyle(Theme.secondary)
                }
            }
        }
    }
}

private struct HabitRow: View {
    @Environment(\.modelContext) private var context
    let habit: Habit

    var body: some View {
        let streak = habit.currentStreak
        let logged = habit.isLoggedToday

        GlassCard(tint: logged ? habit.color : nil, padding: 16) {
            HStack(spacing: 14) {
                IconBadge(systemName: habit.icon, colors: [habit.color, habit.color.opacity(0.55)], size: 44)

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Text(habit.name).font(.headline)
                        Button {
                            withAnimation(.spring) {
                                habit.isPriority.toggle()
                                HubActions.save(context)
                            }
                        } label: {
                            Image(systemName: habit.isPriority ? "star.fill" : "star")
                                .font(.subheadline)
                                .foregroundStyle(habit.isPriority ? HubSection.finances.tint : Theme.tertiary)
                                .contentTransition(.symbolEffect(.replace))
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel(habit.isPriority ? "Remove priority" : "Mark as priority")
                    }
                    HStack(spacing: 4) {
                        Image(systemName: "flame.fill").foregroundStyle(streak > 0 ? HubSection.finances.colors[1] : Theme.tertiary)
                        Text(streak == 1 ? "1 day" : "\(streak) days").monospacedDigit()
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.secondary)
                    WeekDots(habit: habit)
                }

                Spacer()

                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.6)) {
                        HubActions.setHabit(habit, logged: !logged, in: context)
                    }
                } label: {
                    Image(systemName: logged ? "checkmark" : "plus")
                        .font(.system(size: 20, weight: .heavy))
                        .foregroundStyle(logged ? .black : .white)
                        .frame(width: 52, height: 52)
                        .background(logged ? habit.color : Color.white.opacity(0.08), in: .circle)
                        .contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(.borderless)
                .sensoryFeedback(.success, trigger: logged) { _, new in new }
                .accessibilityLabel(logged ? "Undo today's log" : "Log for today")
            }
        }
    }
}

private struct WeekDots: View {
    let habit: Habit

    var body: some View {
        let cal = Calendar.current
        let days = (0..<7).reversed().map { cal.date(byAdding: .day, value: -$0, to: .now.startOfDay)! }
        let logged = habit.loggedDays
        HStack(spacing: 5) {
            ForEach(days, id: \.self) { day in
                VStack(spacing: 2) {
                    Circle()
                        .fill(logged.contains(day) ? habit.color : Color.white.opacity(0.1))
                        .frame(width: 10, height: 10)
                    Text(day.formatted(.dateTime.weekday(.narrow)))
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(Theme.tertiary)
                }
            }
        }
    }
}

private struct HabitDetail: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    let habit: Habit
    @State private var editing = false

    private let weeks = 16

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(spacing: 14) {
                        IconBadge(systemName: habit.icon, colors: [habit.color, habit.color.opacity(0.55)], size: 56)
                        VStack(alignment: .leading) {
                            Text(habit.name).font(.display(28))
                            if habit.isPriority {
                                Label("Priority", systemImage: "star.fill").font(.caption.weight(.bold))
                                    .foregroundStyle(HubSection.finances.tint)
                            }
                        }
                    }

                    HStack(spacing: 12) {
                        stat("Current", "\(habit.currentStreak)", "flame.fill")
                        stat("Best", "\(habit.bestStreak)", "trophy.fill")
                        stat("Total", "\(habit.loggedDays.count)", "checkmark.circle.fill")
                    }
                    .fixedSize(horizontal: false, vertical: true)

                    GlassCard {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Last \(weeks) weeks").font(.headline)
                            heatmap
                            Text("Tap a day to toggle it.").font(.caption).foregroundStyle(Theme.tertiary)
                        }
                    }

                    Toggle("Priority habit", isOn: Binding(
                        get: { habit.isPriority },
                        set: { habit.isPriority = $0; HubActions.save(context) }
                    ))
                    .padding(16)
                    .glassEffect(.regular, in: .rect(cornerRadius: 18))
                }
                .padding(20)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .primaryAction) { Button("Edit") { editing = true } }
            }
            .sheet(isPresented: $editing) { HabitEditor(habit: habit) }
        }
    }

    private func stat(_ label: String, _ value: String, _ icon: String) -> some View {
        GlassCard(tint: habit.color, padding: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Image(systemName: icon).foregroundStyle(habit.color)
                Text(value).font(.display(26))
                Text(label).font(.caption).foregroundStyle(Theme.secondary)
            }
        }
    }

    private var heatmap: some View {
        let cal = Calendar.current
        let today = Date.now.startOfDay
        let weekStart = cal.dateInterval(of: .weekOfYear, for: today)!.start
        let first = cal.date(byAdding: .weekOfYear, value: -(weeks - 1), to: weekStart)!
        let logged = habit.loggedDays

        return HStack(spacing: 4) {
            ForEach(0..<weeks, id: \.self) { week in
                VStack(spacing: 4) {
                    ForEach(0..<7, id: \.self) { weekday in
                        let day = cal.date(byAdding: .day, value: week * 7 + weekday, to: first)!
                        RoundedRectangle(cornerRadius: 3)
                            .fill(day > today ? Color.clear : logged.contains(day) ? habit.color : Color.white.opacity(0.08))
                            .aspectRatio(1, contentMode: .fit)
                            .onTapGesture {
                                guard day <= today else { return }
                                withAnimation { HubActions.setHabit(habit, logged: !logged.contains(day), on: day, in: context) }
                            }
                    }
                }
            }
        }
    }
}

struct HabitEditor: View {
    static let icons = ["flame.fill", "figure.run", "dumbbell.fill", "book.fill", "drop.fill", "bed.double.fill",
                        "brain.head.profile", "leaf.fill", "pencil", "music.note", "heart.fill", "sun.max.fill",
                        "fork.knife", "pills.fill", "graduationcap.fill", "dollarsign.circle.fill", "figure.walk", "moon.fill"]

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    let habit: Habit?
    @State private var name: String
    @State private var icon: String
    @State private var colorHex: String
    @State private var isPriority: Bool

    init(habit: Habit?) {
        self.habit = habit
        _name = State(initialValue: habit?.name ?? "")
        _icon = State(initialValue: habit?.icon ?? "flame.fill")
        _colorHex = State(initialValue: habit?.colorHex ?? Theme.palette[0])
        _isPriority = State(initialValue: habit?.isPriority ?? false)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 14) {
                        IconBadge(systemName: icon, colors: [Color(hex: colorHex), Color(hex: colorHex).opacity(0.55)], size: 48)
                        TextField("Habit name", text: $name).font(.headline)
                    }
                    Toggle("Priority", isOn: $isPriority)
                }
                Section("Color") { ColorSwatchPicker(selection: $colorHex) }
                Section("Icon") { IconPicker(icons: Self.icons, selection: $icon, color: Color(hex: colorHex)) }
            }
            .navigationTitle(habit == nil ? "New habit" : "Edit habit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save).disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        if let habit {
            habit.name = trimmed
            habit.icon = icon
            habit.colorHex = colorHex
            habit.isPriority = isPriority
            HubActions.save(context)
        } else {
            HubActions.addHabit(name: trimmed, icon: icon, colorHex: colorHex, isPriority: isPriority, in: context)
        }
        GDashShortcuts.updateAppShortcutParameters()
        dismiss()
    }
}
