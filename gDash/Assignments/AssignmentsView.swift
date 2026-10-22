import SwiftData
import SwiftUI

struct AssignmentsView: View {
    enum Filter: String, CaseIterable, Identifiable {
        case active = "Active", completed = "Completed", all = "All"
        var id: String { rawValue }
    }

    @Environment(\.modelContext) private var context
    @Query(sort: \Assignment.dueDate) private var assignments: [Assignment]
    @State private var filter: Filter = .active
    @State private var editing: Assignment?
    @State private var showingNew = false

    private var shown: [Assignment] {
        switch filter {
        case .active: assignments.filter { !$0.isCompleted }
        case .completed: assignments.filter(\.isCompleted).sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }
        case .all: assignments
        }
    }

    var body: some View {
        List {
            Section {
                summary
                Picker("Filter", selection: $filter) {
                    ForEach(Filter.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
            }
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)

            if shown.isEmpty {
                EmptyHint(icon: "checklist", title: filter == .completed ? "Nothing finished yet" : "No assignments",
                          message: "Tap + to add one, or ask the assistant.")
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }

            ForEach(shown) { assignment in
                AssignmentRow(assignment: assignment) {
                    withAnimation(.spring) {
                        assignment.toggleComplete()
                        HubActions.save(context)
                    }
                }
                .contentShape(.rect)
                .onTapGesture { editing = assignment }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 6, leading: 18, bottom: 6, trailing: 18))
                .swipeActions(edge: .leading) {
                    Button {
                        assignment.toggleComplete()
                        HubActions.save(context)
                    } label: {
                        Label(assignment.isCompleted ? "Reopen" : "Complete",
                              systemImage: assignment.isCompleted ? "arrow.uturn.backward" : "checkmark")
                    }
                    .tint(Theme.success)
                }
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        context.delete(assignment)
                        HubActions.save(context)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(HubBackground(accent: HubSection.assignments.tint))
        .navigationTitle("Assignments")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Add", systemImage: "plus") { showingNew = true }
            }
        }
        .sheet(isPresented: $showingNew) { AssignmentEditor(assignment: nil) }
        .sheet(item: $editing) { AssignmentEditor(assignment: $0) }
    }

    private var summary: some View {
        let open = assignments.filter { !$0.isCompleted }
        let overdue = open.filter(\.isOverdue).count
        let average = open.isEmpty ? 1 : open.reduce(0) { $0 + $1.progress } / Double(open.count)

        return GlassCard(tint: HubSection.assignments.tint) {
            HStack(spacing: 18) {
                ZStack {
                    ProgressRing(value: average, colors: HubSection.assignments.colors, lineWidth: 10)
                    Text("\(Int(average * 100))%").font(.display(18, weight: .bold))
                }
                .frame(width: 78, height: 78)
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(open.count) open").font(.display(26))
                    Text(overdue > 0 ? "\(overdue) overdue" : "Nothing overdue")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(overdue > 0 ? Theme.danger : Theme.secondary)
                    Text("\(assignments.count - open.count) completed")
                        .font(.caption)
                        .foregroundStyle(Theme.tertiary)
                }
            }
        }
    }
}

private struct AssignmentRow: View {
    let assignment: Assignment
    let onToggle: () -> Void

    var body: some View {
        GlassCard(padding: 16) {
            HStack(alignment: .top, spacing: 14) {
                Button(action: onToggle) {
                    Image(systemName: assignment.isCompleted ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundStyle(assignment.isCompleted ? Theme.success : Theme.tertiary)
                        .contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(.borderless)

                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(assignment.title)
                            .font(.headline)
                            .strikethrough(assignment.isCompleted)
                            .foregroundStyle(assignment.isCompleted ? Theme.secondary : .white)
                        Spacer()
                        Circle().fill(assignment.priority.color).frame(width: 8, height: 8)
                    }
                    HStack(spacing: 6) {
                        if !assignment.course.isEmpty {
                            Text(assignment.course).fontWeight(.semibold)
                            Text("·")
                        }
                        Text(assignment.isCompleted ? "Done" : assignment.dueDate.dueDescription)
                            .foregroundStyle(assignment.isOverdue ? Theme.danger : Theme.secondary)
                    }
                    .font(.caption)
                    .foregroundStyle(Theme.secondary)

                    HStack(spacing: 10) {
                        GradientProgressBar(value: assignment.progress, colors: HubSection.assignments.colors)
                        Text("\(Int(assignment.progress * 100))%")
                            .font(.caption.monospacedDigit().weight(.bold))
                            .frame(width: 40, alignment: .trailing)
                    }
                }
            }
        }
    }
}

struct AssignmentEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    let assignment: Assignment?
    @State private var title: String
    @State private var course: String
    @State private var notes: String
    @State private var due: Date
    @State private var priority: Priority
    @State private var progress: Double

    init(assignment: Assignment?, defaultDue: Date? = nil) {
        self.assignment = assignment
        let fallbackDue = Calendar.current.date(bySettingHour: 23, minute: 59, second: 0,
                                                of: Calendar.current.date(byAdding: .day, value: 1, to: .now)!)!
        _title = State(initialValue: assignment?.title ?? "")
        _course = State(initialValue: assignment?.course ?? "")
        _notes = State(initialValue: assignment?.notes ?? "")
        _due = State(initialValue: assignment?.dueDate ?? defaultDue ?? fallbackDue)
        _priority = State(initialValue: assignment?.priority ?? .medium)
        _progress = State(initialValue: assignment?.progress ?? 0)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Title", text: $title)
                        .font(.headline)
                    TextField("Course or project", text: $course)
                }
                Section("Due") {
                    DatePicker("Due", selection: $due)
                    Picker("Priority", selection: $priority) {
                        ForEach(Priority.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
                Section("Progress") {
                    HStack(spacing: 16) {
                        ZStack {
                            ProgressRing(value: progress, colors: HubSection.assignments.colors, lineWidth: 8)
                            Text("\(Int(progress * 100))%").font(.display(15, weight: .bold))
                        }
                        .frame(width: 64, height: 64)
                        VStack {
                            Slider(value: $progress, in: 0...1, step: 0.05)
                            HStack {
                                ForEach([0.25, 0.5, 0.75, 1.0], id: \.self) { step in
                                    Button("\(Int(step * 100))%") { withAnimation { progress = step } }
                                        .buttonStyle(.bordered)
                                        .controlSize(.small)
                                }
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
                Section("Notes") {
                    TextField("Notes", text: $notes, axis: .vertical)
                        .lineLimit(3...8)
                }
                if let assignment {
                    Section {
                        Button("Delete assignment", role: .destructive) {
                            context.delete(assignment)
                            HubActions.save(context)
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle(assignment == nil ? "New assignment" : "Edit assignment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save).disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func save() {
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        let target = assignment ?? HubActions.addAssignment(title: trimmed, due: due, in: context)
        target.title = trimmed
        target.course = course
        target.notes = notes
        target.dueDate = due
        target.priority = priority
        target.setProgress(progress)
        HubActions.save(context)
        dismiss()
    }
}
