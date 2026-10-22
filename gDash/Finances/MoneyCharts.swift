import Charts
import SwiftUI

/// Categorical chart hues, validated for CVD separation and contrast on the dark surface.
/// Assigned in fixed order; anything past the last slot folds into "Other".
enum ChartPalette {
    static let categorical = ["0891B2", "D97706", "8B5CF6", "65A30D", "EC4899", "3B82F6"].map { Color(hex: $0) }
    static let neutral = Color(hex: "64748B")
    static let income = categorical[0]
    static let spent = categorical[1]
}

// MARK: - Money flow (Sankey)

struct FlowNode: Identifiable {
    let label: String
    let value: Double
    let color: Color
    var id: String { label }
}

struct MoneyFlow {
    var sources: [FlowNode] = []
    var sinks: [FlowNode] = []
    var total: Double = 0

    /// Income sources on the left flow into spending categories (plus savings) on the right.
    /// Category colors follow budget creation order so a category keeps its hue across months.
    static func build(entries: [MoneyEntry], budgets: [Budget]) -> MoneyFlow {
        let income = Dictionary(grouping: entries.filter(\.isIncome)) { $0.category.isEmpty ? $0.title : $0.category }
            .mapValues { $0.reduce(0) { $0 + $1.amount } }
        let expense = Dictionary(grouping: entries.filter { !$0.isIncome }) { $0.category.isEmpty ? "Uncategorized" : $0.category }
            .mapValues { $0.reduce(0) { $0 + $1.amount } }

        let budgetOrder = budgets.sorted { $0.createdAt < $1.createdAt }.map { $0.name.lowercased() }
        let orderedCategories = expense.keys.sorted { lhs, rhs in
            let l = budgetOrder.firstIndex(of: lhs.lowercased()) ?? Int.max
            let r = budgetOrder.firstIndex(of: rhs.lowercased()) ?? Int.max
            return l == r ? lhs < rhs : l < r
        }

        var flow = MoneyFlow()
        let slots = ChartPalette.categorical.count
        for (index, name) in orderedCategories.enumerated() where index < slots - 1 || orderedCategories.count == slots {
            flow.sinks.append(FlowNode(label: name, value: expense[name]!, color: ChartPalette.categorical[index]))
        }
        if orderedCategories.count > slots {
            let other = orderedCategories[(slots - 1)...].reduce(0) { $0 + expense[$1]! }
            flow.sinks.append(FlowNode(label: "Other", value: other, color: ChartPalette.neutral))
        }

        flow.sources = income.sorted { $0.value > $1.value }
            .map { FlowNode(label: $0.key, value: $0.value, color: ChartPalette.neutral) }

        let totalIn = income.values.reduce(0, +)
        let totalOut = expense.values.reduce(0, +)
        if totalIn > totalOut {
            flow.sinks.append(FlowNode(label: "Saved", value: totalIn - totalOut, color: Theme.success))
        } else if totalOut > totalIn {
            flow.sources.append(FlowNode(label: "From savings", value: totalOut - totalIn, color: Theme.danger))
        }
        flow.total = max(totalIn, totalOut)
        return flow
    }
}

struct MoneyFlowChart: View {
    let flow: MoneyFlow

    private let nodeWidth: CGFloat = 8
    private let labelWidth: CGFloat = 92
    private let gap: CGFloat = 6

    var body: some View {
        if flow.total <= 0 {
            Text("Add income or expenses this month to see where your money goes.")
                .font(.subheadline)
                .foregroundStyle(Theme.secondary)
                .frame(maxWidth: .infinity, minHeight: 120)
        } else {
            Canvas { context, size in draw(in: &context, size: size) }
                .frame(height: max(200, CGFloat(max(flow.sources.count, flow.sinks.count)) * 40))
                .accessibilityElement()
                .accessibilityLabel(accessibilitySummary)
        }
    }

    private func layout(_ nodes: [FlowNode], height: CGFloat) -> [CGRect] {
        let usable = height - gap * CGFloat(max(nodes.count - 1, 0))
        var y: CGFloat = 0
        return nodes.map { node in
            let h = max(2, usable * node.value / flow.total)
            defer { y += h + gap }
            return CGRect(x: 0, y: y, width: nodeWidth, height: h)
        }
    }

    private func draw(in context: inout GraphicsContext, size: CGSize) {
        let leftX = labelWidth
        let rightX = size.width - labelWidth - nodeWidth
        let left = layout(flow.sources, height: size.height).map { $0.offsetBy(dx: leftX, dy: 0) }
        let right = layout(flow.sinks, height: size.height).map { $0.offsetBy(dx: rightX, dy: 0) }

        // Each source splits across sinks in proportion to their share of the total.
        var leftCursor = left.map(\.minY)
        var rightCursor = right.map(\.minY)
        for (i, source) in flow.sources.enumerated() {
            for (j, sink) in flow.sinks.enumerated() {
                let lh = left[i].height * (sink.value / flow.total)
                let rh = right[j].height * (source.value / flow.total)
                guard lh > 0, rh > 0 else { continue }
                let x0 = left[i].maxX, x1 = right[j].minX, mid = (x0 + x1) / 2
                let y0 = leftCursor[i], y1 = rightCursor[j]
                var path = Path()
                path.move(to: CGPoint(x: x0, y: y0))
                path.addCurve(to: CGPoint(x: x1, y: y1), control1: CGPoint(x: mid, y: y0), control2: CGPoint(x: mid, y: y1))
                path.addLine(to: CGPoint(x: x1, y: y1 + rh))
                path.addCurve(to: CGPoint(x: x0, y: y0 + lh), control1: CGPoint(x: mid, y: y1 + rh), control2: CGPoint(x: mid, y: y0 + lh))
                path.closeSubpath()
                context.fill(path, with: .linearGradient(
                    Gradient(colors: [source.color.opacity(0.35), sink.color.opacity(0.55)]),
                    startPoint: CGPoint(x: x0, y: 0), endPoint: CGPoint(x: x1, y: 0)))
                leftCursor[i] += lh
                rightCursor[j] += rh
            }
        }

        for (node, rect) in zip(flow.sources, left) {
            context.fill(Path(roundedRect: rect, cornerRadius: 3), with: .color(node.color))
            drawLabel(node, in: &context, at: CGPoint(x: rect.minX - 8, y: rect.midY), anchor: .trailing)
        }
        for (node, rect) in zip(flow.sinks, right) {
            context.fill(Path(roundedRect: rect, cornerRadius: 3), with: .color(node.color))
            drawLabel(node, in: &context, at: CGPoint(x: rect.maxX + 8, y: rect.midY), anchor: .leading)
        }
    }

    private func drawLabel(_ node: FlowNode, in context: inout GraphicsContext, at point: CGPoint, anchor: UnitPoint) {
        context.draw(context.resolve(Text(node.label).font(.caption2.weight(.semibold)).foregroundStyle(.white)),
                     at: CGPoint(x: point.x, y: point.y - 7), anchor: anchor)
        context.draw(context.resolve(Text(node.value.currency).font(.caption2.monospacedDigit()).foregroundStyle(Theme.secondary)),
                     at: CGPoint(x: point.x, y: point.y + 7), anchor: anchor)
    }

    private var accessibilitySummary: String {
        let ins = flow.sources.map { "\($0.label) \($0.value.currency)" }.joined(separator: ", ")
        let outs = flow.sinks.map { "\($0.label) \($0.value.currency)" }.joined(separator: ", ")
        return "Money in: \(ins). Money out: \(outs)."
    }
}

// MARK: - Six-month cash flow

struct CashFlowChart: View {
    struct Point: Identifiable {
        let month: Date
        let series: String
        let amount: Double
        var id: String { "\(series)-\(month.timeIntervalSince1970)" }
    }

    let entries: [MoneyEntry]
    @State private var selectedMonth: Date?

    private var points: [Point] {
        let cal = Calendar.current
        let thisMonth = cal.dateInterval(of: .month, for: .now)!.start
        return (0..<6).reversed().flatMap { offset -> [Point] in
            let month = cal.date(byAdding: .month, value: -offset, to: thisMonth)!
            let inMonth = entries.filter { cal.isDate($0.date, equalTo: month, toGranularity: .month) }
            return [
                Point(month: month, series: "Income", amount: inMonth.filter(\.isIncome).reduce(0) { $0 + $1.amount }),
                Point(month: month, series: "Spent", amount: inMonth.filter { !$0.isIncome }.reduce(0) { $0 + $1.amount }),
            ]
        }
    }

    var body: some View {
        let data = points
        Chart {
            ForEach(data) { point in
                BarMark(x: .value("Month", point.month, unit: .month),
                        y: .value("Amount", point.amount),
                        width: .ratio(0.7))
                    .foregroundStyle(by: .value("Series", point.series))
                    .position(by: .value("Series", point.series))
                    .clipShape(UnevenRoundedRectangle(topLeadingRadius: 4, topTrailingRadius: 4))
            }
            if let selectedMonth {
                RuleMark(x: .value("Month", selectedMonth, unit: .month))
                    .foregroundStyle(Color.white.opacity(0.12))
                    .lineStyle(StrokeStyle(lineWidth: 24))
                    .zIndex(-1)
                    .annotation(position: .top, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                        tooltip(for: selectedMonth, in: data)
                    }
            }
        }
        .chartForegroundStyleScale(["Income": ChartPalette.income, "Spent": ChartPalette.spent])
        .chartXSelection(value: $selectedMonth)
        .chartXAxis {
            AxisMarks(values: .stride(by: .month)) { _ in
                AxisValueLabel(format: .dateTime.month(.abbreviated), centered: true)
                    .foregroundStyle(Theme.secondary)
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
                AxisGridLine().foregroundStyle(Theme.hairline)
                AxisValueLabel {
                    if let amount = value.as(Double.self) {
                        Text(amount, format: .currency(code: Locale.current.currency?.identifier ?? "USD").precision(.fractionLength(0)))
                    }
                }
                .foregroundStyle(Theme.secondary)
            }
        }
        .chartLegend(position: .top, alignment: .leading)
        .frame(height: 190)
    }

    private func tooltip(for month: Date, in data: [Point]) -> some View {
        let rows = data.filter { Calendar.current.isDate($0.month, equalTo: month, toGranularity: .month) }
        return VStack(alignment: .leading, spacing: 4) {
            Text(month.formatted(.dateTime.month(.wide).year())).font(.caption.weight(.bold))
            ForEach(rows) { row in
                HStack(spacing: 6) {
                    Circle().fill(row.series == "Income" ? ChartPalette.income : ChartPalette.spent).frame(width: 7, height: 7)
                    Text(row.series).foregroundStyle(Theme.secondary)
                    Spacer(minLength: 12)
                    Text(row.amount.currency).monospacedDigit()
                }
                .font(.caption)
            }
        }
        .padding(10)
        .frame(width: 170)
        .glassEffect(.regular, in: .rect(cornerRadius: 12))
    }
}
