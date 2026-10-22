import SwiftData
import SwiftUI

struct FinancesView: View {
    private enum SheetKind: Identifiable {
        case entry(isIncome: Bool), budget(Budget?), bill(Bill?)

        var id: String {
            switch self {
            case .entry(let income): "entry-\(income)"
            case .budget(let budget): "budget-\(budget?.id.uuidString ?? "new")"
            case .bill(let bill): "bill-\(bill?.id.uuidString ?? "new")"
            }
        }
    }

    @Environment(\.modelContext) private var context
    @Query(sort: \Budget.createdAt) private var budgets: [Budget]
    @Query(sort: \MoneyEntry.date, order: .reverse) private var entries: [MoneyEntry]
    @Query(sort: \Bill.dueDate) private var bills: [Bill]
    @State private var sheet: SheetKind?

    private var monthEntries: [MoneyEntry] {
        entries.filter { Calendar.current.isDate($0.date, equalTo: .now, toGranularity: .month) }
    }

    var body: some View {
        let income = monthEntries.filter(\.isIncome).reduce(0) { $0 + $1.amount }
        let spent = monthEntries.filter { !$0.isIncome }.reduce(0) { $0 + $1.amount }

        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                summary(income: income, spent: spent)

                GlassCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Money flow · \(Date.now.formatted(.dateTime.month(.wide)))").font(.headline)
                        MoneyFlowChart(flow: MoneyFlow.build(entries: monthEntries, budgets: budgets))
                    }
                }

                GlassCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Cash flow · 6 months").font(.headline)
                        CashFlowChart(entries: entries)
                    }
                }

                billsSection
                budgetsSection
                activitySection
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 40)
        }
        .background(HubBackground(accent: HubSection.finances.tint))
        .navigationTitle("Finances")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Expense", systemImage: "minus.circle") { sheet = .entry(isIncome: false) }
                    Button("Income", systemImage: "plus.circle") { sheet = .entry(isIncome: true) }
                    Button("Budget", systemImage: "chart.pie") { sheet = .budget(nil) }
                    Button("Bill or card", systemImage: "creditcard") { sheet = .bill(nil) }
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(item: $sheet) { kind in
            switch kind {
            case .entry(let isIncome): EntryEditor(isIncome: isIncome, categories: budgets.map(\.name))
            case .budget(let budget): BudgetEditor(budget: budget)
            case .bill(let bill): BillEditor(bill: bill)
            }
        }
    }

    private func summary(income: Double, spent: Double) -> some View {
        let net = income - spent
        return VStack(alignment: .leading, spacing: 14) {
            Eyebrow(text: "Net this month", color: .black.opacity(0.6))
            Text((net >= 0 ? "+" : "−") + abs(net).currency)
                .font(.display(44))
                .foregroundStyle(.black)
                .contentTransition(.numericText())
            HStack(spacing: 10) {
                pill("In", income, "arrow.down.left")
                pill("Out", spent, "arrow.up.right")
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(HubSection.finances.gradient, in: .rect(cornerRadius: Theme.corner))
    }

    private func pill(_ label: String, _ value: Double, _ icon: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
            Text("\(label) \(value.currency)").monospacedDigit()
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(.black.opacity(0.8))
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.black.opacity(0.1), in: .capsule)
    }

    // MARK: Bills

    private var billsSection: some View {
        let upcoming = bills.filter { !$0.isPaid }
        return VStack(alignment: .leading, spacing: 10) {
            SectionTitle(title: "Bills due soon", trailing: upcoming.isEmpty ? nil : upcoming.prefix(5).reduce(0) { $0 + $1.amount }.currency)
            if upcoming.isEmpty {
                Text("No upcoming bills.").font(.subheadline).foregroundStyle(Theme.tertiary)
            }
            ForEach(upcoming.prefix(5)) { bill in
                let overdue = bill.dueDate < .now.startOfDay
                let soon = bill.dueDate.timeIntervalSinceNow < 3 * 86400
                GlassCard(tint: overdue ? Theme.danger : nil, padding: 14) {
                    HStack(spacing: 12) {
                        IconBadge(systemName: bill.isCreditCard ? "creditcard.fill" : "doc.plaintext.fill",
                                  colors: HubSection.finances.colors, size: 38)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(bill.name).font(.subheadline.weight(.semibold))
                            HStack(spacing: 4) {
                                if overdue || soon {
                                    Image(systemName: "exclamationmark.circle.fill")
                                }
                                Text(bill.dueDate.dueDescription)
                            }
                            .font(.caption)
                            .foregroundStyle(overdue ? Theme.danger : soon ? HubSection.finances.tint : Theme.secondary)
                        }
                        Spacer()
                        Text(bill.amount.currency).font(.subheadline.weight(.bold)).monospacedDigit()
                        Button("Pay") { withAnimation { HubActions.pay(bill, in: context) } }
                            .buttonStyle(.glassProminent)
                            .tint(HubSection.finances.tint)
                            .controlSize(.small)
                    }
                }
                .contentShape(.rect)
                .onTapGesture { sheet = .bill(bill) }
            }
        }
    }

    // MARK: Budgets

    private var budgetsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle(title: "Budgets", trailing: budgets.isEmpty ? nil : "\(budgets.reduce(0) { $0 + $1.limit }.currency)/mo")
            if budgets.isEmpty {
                Button { sheet = .budget(nil) } label: {
                    Label("Create your first budget", systemImage: "plus")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.glass)
            }
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                ForEach(budgets) { budget in
                    let spent = HubActions.spent(on: budget, entries: entries)
                    let ratio = budget.limit > 0 ? spent / budget.limit : 0
                    Button { sheet = .budget(budget) } label: {
                        GlassCard(tint: budget.color, padding: 14) {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Image(systemName: budget.icon).foregroundStyle(budget.color)
                                    Spacer()
                                    if ratio > 1 {
                                        Label("Over", systemImage: "exclamationmark.triangle.fill")
                                            .font(.caption2.weight(.bold))
                                            .foregroundStyle(Theme.danger)
                                    }
                                }
                                Text(budget.name).font(.subheadline.weight(.semibold)).lineLimit(1)
                                Text(spent.currency).font(.display(20)).monospacedDigit()
                                GradientProgressBar(value: ratio,
                                                    colors: ratio > 1 ? [Theme.danger, Theme.danger] : [budget.color, budget.color.opacity(0.6)],
                                                    height: 6)
                                Text("\(max(budget.limit - spent, 0).currency) left of \(budget.limit.currency)")
                                    .font(.caption2)
                                    .foregroundStyle(Theme.secondary)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.8)
                            }
                        }
                    }
                    .buttonStyle(CardPressStyle())
                    .foregroundStyle(.white)
                }
            }
        }
    }

    // MARK: Activity

    private var activitySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle(title: "Recent activity")
            if entries.isEmpty {
                Text("No transactions yet.").font(.subheadline).foregroundStyle(Theme.tertiary)
            }
            GlassCard(padding: 6) {
                VStack(spacing: 0) {
                    ForEach(Array(entries.prefix(12).enumerated()), id: \.element.id) { index, entry in
                        HStack(spacing: 12) {
                            Image(systemName: entry.isIncome ? "arrow.down.left" : "arrow.up.right")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(entry.isIncome ? Theme.success : Theme.secondary)
                                .frame(width: 30, height: 30)
                                .background(Color.white.opacity(0.06), in: .circle)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(entry.title).font(.subheadline.weight(.semibold))
                                Text("\(entry.category) · \(entry.date.formatted(.dateTime.month(.abbreviated).day()))")
                                    .font(.caption)
                                    .foregroundStyle(Theme.secondary)
                            }
                            Spacer()
                            Text((entry.isIncome ? "+" : "−") + entry.amount.currency)
                                .font(.subheadline.weight(.bold).monospacedDigit())
                                .foregroundStyle(entry.isIncome ? Theme.success : .white)
                        }
                        .padding(10)
                        .contextMenu {
                            Button("Delete", systemImage: "trash", role: .destructive) {
                                context.delete(entry)
                                HubActions.save(context)
                            }
                        }
                        if index < min(entries.count, 12) - 1 {
                            Divider().overlay(Theme.hairline).padding(.leading, 52)
                        }
                    }
                }
            }
            .opacity(entries.isEmpty ? 0 : 1)
        }
    }
}

// MARK: - Editors

private let currencyCode = Locale.current.currency?.identifier ?? "USD"

struct EntryEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    let isIncome: Bool
    let categories: [String]
    @State private var title = ""
    @State private var amount: Double?
    @State private var category = ""
    @State private var date = Date.now

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Amount", value: $amount, format: .currency(code: currencyCode))
                        .font(.display(32))
                        .keyboardType(.decimalPad)
                    TextField(isIncome ? "Source (e.g. Paycheck)" : "What was it?", text: $title)
                }
                Section(isIncome ? "Income category" : "Budget category") {
                    TextField("Category", text: $category)
                    if !categories.isEmpty && !isIncome {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack {
                                ForEach(categories, id: \.self) { name in
                                    Button(name) { category = name }
                                        .buttonStyle(.bordered)
                                        .tint(category == name ? HubSection.finances.tint : .gray)
                                }
                            }
                        }
                    }
                }
                Section { DatePicker("Date", selection: $date, displayedComponents: .date) }
            }
            .navigationTitle(isIncome ? "Add income" : "Add expense")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let name = title.trimmingCharacters(in: .whitespaces)
                        let cat = category.trimmingCharacters(in: .whitespaces)
                        HubActions.addEntry(title: name.isEmpty ? (cat.isEmpty ? "Untitled" : cat) : name,
                                            amount: amount ?? 0, isIncome: isIncome,
                                            category: cat.isEmpty ? (isIncome ? "Income" : "Uncategorized") : cat,
                                            date: date, in: context)
                        dismiss()
                    }
                    .disabled((amount ?? 0) <= 0)
                }
            }
        }
    }
}

struct BudgetEditor: View {
    static let icons = ["cart.fill", "fork.knife", "car.fill", "house.fill", "bag.fill", "gamecontroller.fill",
                        "airplane", "cross.case.fill", "graduationcap.fill", "creditcard.fill", "gift.fill", "tshirt.fill"]

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    let budget: Budget?
    @State private var name: String
    @State private var limit: Double?
    @State private var icon: String
    @State private var colorHex: String

    init(budget: Budget?) {
        self.budget = budget
        _name = State(initialValue: budget?.name ?? "")
        _limit = State(initialValue: budget?.limit)
        _icon = State(initialValue: budget?.icon ?? "cart.fill")
        _colorHex = State(initialValue: budget?.colorHex ?? "FBBF24")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Category (e.g. Groceries)", text: $name).font(.headline)
                    TextField("Monthly limit", value: $limit, format: .currency(code: currencyCode))
                        .keyboardType(.decimalPad)
                }
                Section("Color") { ColorSwatchPicker(selection: $colorHex) }
                Section("Icon") { IconPicker(icons: Self.icons, selection: $icon, color: Color(hex: colorHex)) }
                if let budget {
                    Section {
                        Button("Delete budget", role: .destructive) {
                            context.delete(budget)
                            HubActions.save(context)
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle(budget == nil ? "New budget" : "Edit budget")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let target = budget ?? HubActions.setBudget(category: name, limit: limit ?? 0, in: context)
                        target.name = name.trimmingCharacters(in: .whitespaces)
                        target.limit = limit ?? 0
                        target.icon = icon
                        target.colorHex = colorHex
                        HubActions.save(context)
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || (limit ?? 0) <= 0)
                }
            }
        }
    }
}

struct BillEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    let bill: Bill?
    @State private var name: String
    @State private var amount: Double?
    @State private var due: Date
    @State private var isCreditCard: Bool
    @State private var repeatsMonthly: Bool

    init(bill: Bill?) {
        self.bill = bill
        _name = State(initialValue: bill?.name ?? "")
        _amount = State(initialValue: bill?.amount)
        _due = State(initialValue: bill?.dueDate ?? .now)
        _isCreditCard = State(initialValue: bill?.isCreditCard ?? false)
        _repeatsMonthly = State(initialValue: bill?.repeatsMonthly ?? true)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name).font(.headline)
                    TextField("Amount", value: $amount, format: .currency(code: currencyCode))
                        .keyboardType(.decimalPad)
                    DatePicker("Due", selection: $due, displayedComponents: .date)
                }
                Section {
                    Toggle("Credit card payment", isOn: $isCreditCard)
                    Toggle("Repeats monthly", isOn: $repeatsMonthly)
                }
                if let bill {
                    Section {
                        Button("Delete bill", role: .destructive) {
                            context.delete(bill)
                            HubActions.save(context)
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle(bill == nil ? "New bill" : "Edit bill")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let trimmed = name.trimmingCharacters(in: .whitespaces)
                        if let bill {
                            bill.name = trimmed
                            bill.amount = amount ?? 0
                            bill.dueDate = due
                            bill.isCreditCard = isCreditCard
                            bill.repeatsMonthly = repeatsMonthly
                            HubActions.save(context)
                        } else {
                            HubActions.addBill(name: trimmed, amount: amount ?? 0, due: due, isCreditCard: isCreditCard,
                                               repeatsMonthly: repeatsMonthly, in: context)
                        }
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || (amount ?? 0) <= 0)
                }
            }
        }
    }
}
