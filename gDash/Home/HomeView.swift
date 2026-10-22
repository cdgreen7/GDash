import SwiftData
import SwiftUI

/// The menu screen: a glance at every section, each card opening its full screen.
struct HomeView: View {
    @Binding var path: [HubSection]
    @Environment(AuthManager.self) private var auth
    @Environment(\.modelContext) private var context

    @Query(sort: \Assignment.dueDate) private var assignments: [Assignment]
    @Query(sort: \Habit.createdAt) private var habits: [Habit]
    @Query(sort: \HubEvent.start) private var events: [HubEvent]
    @Query(sort: \Bill.dueDate) private var bills: [Bill]
    @Query(sort: \Budget.createdAt) private var budgets: [Budget]
    @Query(sort: \MoneyEntry.date, order: .reverse) private var entries: [MoneyEntry]

    var body: some View {
        let suggestions = NextUpEngine.rank(assignments: assignments, habits: habits, bills: bills, events: events)

        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                UpNextCard(suggestions: suggestions) { path.append($0) }

                card(.assignments) { AssignmentsGlance(assignments: assignments) }

                HStack(alignment: .top, spacing: 14) {
                    card(.calendar) { ScheduleGlance(events: events, assignments: assignments, bills: bills) }
                    card(.habits) { HabitsGlance(habits: habits) }
                }
                .fixedSize(horizontal: false, vertical: true)

                card(.finances) { FinanceGlance(budgets: budgets, entries: entries, bills: bills) }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 110)
        }
        .scrollIndicators(.hidden)
        .background(HubBackground())
        .toolbar(.hidden, for: .navigationBar)
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Eyebrow(text: Date.now.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))
                Text(greeting)
                    .font(.display(40))
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
            }
            Spacer()
            ProfileMenu()
        }
        .padding(.top, 12)
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: .now)
        let part = hour < 12 ? "Good morning" : hour < 17 ? "Good afternoon" : "Good evening"
        return auth.firstName.isEmpty ? part : "\(part),\n\(auth.firstName)"
    }

    private func card<Content: View>(_ section: HubSection, @ViewBuilder content: () -> Content) -> some View {
        Button { path.append(section) } label: {
            GlassCard(tint: section.tint) {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        IconBadge(systemName: section.icon, colors: section.colors, size: 34)
                        Text(section.title).font(.headline)
                        Spacer()
                        Image(systemName: "arrow.up.right").font(.footnote.weight(.bold)).foregroundStyle(Theme.tertiary)
                    }
                    content()
                }
            }
        }
        .buttonStyle(CardPressStyle())
    }
}

private struct ProfileMenu: View {
    @Environment(AuthManager.self) private var auth
    @Environment(\.modelContext) private var context

    var body: some View {
        @Bindable var auth = auth
        Menu {
            if !auth.displayName.isEmpty {
                Text(auth.displayName)
            }
            Toggle("Require \(auth.biometryName)", isOn: $auth.requireBiometrics)
            #if DEBUG
            Button("Load sample data", systemImage: "wand.and.stars") { SampleData.load(into: context) }
            #endif
            Button("Sign out", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) { auth.signOut() }
        } label: {
            Text(initials)
                .font(.headline.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 46, height: 46)
                .glassEffect(.regular.tint(HubSection.assistant.tint.opacity(0.3)).interactive(), in: .circle)
        }
    }

    private var initials: String {
        let letters = auth.displayName.split(separator: " ").prefix(2).compactMap(\.first)
        return letters.isEmpty ? "Me" : String(letters)
    }
}

// MARK: - Glance cards

private struct UpNextCard: View {
    let suggestions: [Suggestion]
    let open: (HubSection) -> Void

    var body: some View {
        let top = suggestions.first
        let section = top?.section ?? .assistant

        Button { if let top { open(top.section) } } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Eyebrow(text: "Up next", color: .black.opacity(0.6))
                    Spacer()
                    if let top {
                        Label(top.section.title, systemImage: top.section.icon)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.black.opacity(0.6))
                    }
                }
                Text(top?.title ?? "You're all caught up")
                    .font(.display(28))
                    .foregroundStyle(.black)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
                Text(top?.detail ?? "Nothing urgent. Plan something with the assistant.")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.black.opacity(0.7))
                if suggestions.count > 1 {
                    Text("Then: " + suggestions.dropFirst().prefix(2).map(\.title).joined(separator: " · "))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.black.opacity(0.55))
                        .lineLimit(1)
                        .padding(.top, 2)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(section.gradient, in: .rect(cornerRadius: Theme.corner))
        }
        .buttonStyle(CardPressStyle())
    }
}

private struct AssignmentsGlance: View {
    let assignments: [Assignment]

    var body: some View {
        let open = assignments.filter { !$0.isCompleted }
        let weekEnd = Calendar.current.date(byAdding: .day, value: 7, to: .now)!
        let dueThisWeek = open.filter { $0.dueDate <= weekEnd }.count

        VStack(alignment: .leading, spacing: 12) {
            Text(open.isEmpty ? "Nothing due" : "\(dueThisWeek) due this week")
                .font(.display(24, weight: .bold))
            ForEach(open.prefix(3)) { assignment in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(assignment.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                        Spacer()
                        Text(assignment.dueDate.dueDescription)
                            .font(.caption)
                            .foregroundStyle(assignment.isOverdue ? Theme.danger : Theme.secondary)
                            .lineLimit(1)
                    }
                    GradientProgressBar(value: assignment.progress, colors: HubSection.assignments.colors, height: 6)
                }
            }
        }
        .foregroundStyle(.white)
    }
}

private struct ScheduleGlance: View {
    let events: [HubEvent]
    let assignments: [Assignment]
    let bills: [Bill]

    var body: some View {
        let today = CalendarFeed.items(on: .now, events: events, assignments: assignments, bills: bills)
        let next = today.first { ($0.end ?? $0.start) >= .now && !$0.isDone } ?? today.first

        VStack(alignment: .leading, spacing: 4) {
            Text(Date.now.formatted(.dateTime.day()))
                .font(.display(44))
            Text(today.isEmpty ? "Clear day" : "\(today.count) today")
                .font(.subheadline.weight(.semibold))
            if let next {
                HStack(spacing: 6) {
                    Circle().fill(next.color).frame(width: 7, height: 7)
                    Text(next.title).font(.caption).lineLimit(1)
                }
                .foregroundStyle(Theme.secondary)
                .padding(.top, 4)
            }
        }
        .foregroundStyle(.white)
    }
}

private struct HabitsGlance: View {
    let habits: [Habit]

    var body: some View {
        let done = habits.filter(\.isLoggedToday).count
        let pending = habits.filter { !$0.isLoggedToday }.sorted { $0.isPriority && !$1.isPriority }

        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                ProgressRing(value: habits.isEmpty ? 0 : Double(done) / Double(habits.count),
                             colors: HubSection.habits.colors, lineWidth: 7)
                Text("\(done)/\(habits.count)").font(.display(15, weight: .bold))
            }
            .frame(width: 58, height: 58)
            Text(pending.isEmpty ? (habits.isEmpty ? "No habits yet" : "All logged") : "To log:")
                .font(.subheadline.weight(.semibold))
            if !pending.isEmpty {
                Text(pending.prefix(3).map(\.name).joined(separator: ", "))
                    .font(.caption)
                    .foregroundStyle(Theme.secondary)
                    .lineLimit(2)
            }
        }
        .foregroundStyle(.white)
    }
}

private struct FinanceGlance: View {
    let budgets: [Budget]
    let entries: [MoneyEntry]
    let bills: [Bill]

    var body: some View {
        let monthEntries = entries.filter { Calendar.current.isDate($0.date, equalTo: .now, toGranularity: .month) }
        let spent = monthEntries.filter { !$0.isIncome }.reduce(0) { $0 + $1.amount }
        let totalBudget = budgets.reduce(0) { $0 + $1.limit }
        let nextBill = bills.first { !$0.isPaid }

        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(spent.currency).font(.display(28))
                Text(totalBudget > 0 ? "of \(totalBudget.currency)" : "spent this month")
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondary)
            }
            if totalBudget > 0 {
                GradientProgressBar(value: spent / totalBudget,
                                    colors: spent > totalBudget ? [Theme.danger, Theme.danger] : HubSection.finances.colors)
            }
            if let nextBill {
                Label("\(nextBill.name) · \(nextBill.amount.currency) · \(nextBill.dueDate.dueDescription)",
                      systemImage: nextBill.isCreditCard ? "creditcard.fill" : "calendar.badge.clock")
                    .font(.caption)
                    .foregroundStyle(nextBill.dueDate < .now ? Theme.danger : Theme.secondary)
                    .lineLimit(1)
            }
        }
        .foregroundStyle(.white)
    }
}
