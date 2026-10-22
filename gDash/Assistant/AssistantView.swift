import FoundationModels
import SwiftData
import SwiftUI

struct ChatMessage: Identifiable {
    enum Role { case user, assistant }

    let id = UUID()
    let role: Role
    let text: String
    var actions: [String] = []
}

@MainActor
@Observable
final class AssistantModel {
    var messages: [ChatMessage] = []
    var isThinking = false
    /// Non-nil when Apple Intelligence can't be used; the assistant then runs in command mode.
    var unavailableReason: String?

    private var container: ModelContainer?
    private var session: LanguageModelSession?
    private let activity = ToolActivity()

    func configure(container: ModelContainer) {
        guard self.container == nil else { return }
        self.container = container

        switch SystemLanguageModel.default.availability {
        case .available:
            session = makeSession()
        case .unavailable(.deviceNotEligible):
            unavailableReason = "This device doesn't support Apple Intelligence."
        case .unavailable(.appleIntelligenceNotEnabled):
            unavailableReason = "Turn on Apple Intelligence in Settings to chat freely."
        case .unavailable(.modelNotReady):
            unavailableReason = "Apple Intelligence is still downloading."
        case .unavailable:
            unavailableReason = "Apple Intelligence isn't available right now."
        }

        messages.append(ChatMessage(role: .assistant, text: session != nil
            ? "Hi! I can add tasks and events, log habits, update budgets, or tell you what to tackle next."
            : "I'm in command mode. Try “what next”, “log Workout”, “add task Essay draft”, or “spent 12 on Dining”."))
    }

    private func makeSession() -> LanguageModelSession? {
        guard let container else { return nil }
        let tools: [any Tool] = [
            AddAssignmentTool(container: container, activity: activity),
            AddEventTool(container: container, activity: activity),
            LogHabitTool(container: container, activity: activity),
            SetBudgetTool(container: container, activity: activity),
            RecordMoneyTool(container: container, activity: activity),
            SuggestNextTool(container: container),
            OverviewTool(container: container),
        ]
        let instructions = """
        You are the assistant inside gDash, the user's personal hub for assignments, schedule, habits and finances.
        It is now \(AssistantDate.now). Resolve relative dates like "tomorrow" or "Friday" from that.
        Use tools to make changes; never claim you changed something without calling a tool.
        When the user is unsure what to do, call suggestNext and recommend one item with a short reason.
        Keep replies to one to three friendly sentences.
        """
        return LanguageModelSession(tools: tools, instructions: instructions)
    }

    func send(_ text: String) async {
        let prompt = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty, !isThinking else { return }
        messages.append(ChatMessage(role: .user, text: prompt))
        isThinking = true
        defer { isThinking = false }

        guard let session else {
            messages.append(CommandMode.handle(prompt, container: container))
            return
        }

        do {
            let response = try await session.respond(to: prompt)
            messages.append(ChatMessage(role: .assistant, text: response.content, actions: activity.drain()))
        } catch LanguageModelSession.GenerationError.exceededContextWindowSize {
            // The on-device context is small; start fresh and let the user retry.
            self.session = makeSession()
            messages.append(ChatMessage(role: .assistant, text: "Our chat got long, so I started a fresh one. Could you say that again?",
                                        actions: activity.drain()))
        } catch {
            messages.append(ChatMessage(role: .assistant, text: "Sorry, I couldn't do that. \(error.localizedDescription)",
                                        actions: activity.drain()))
        }
    }

    func reset() {
        session = makeSession()
        messages = Array(messages.prefix(1))
    }
}

/// Offline fallback when Apple Intelligence is unavailable: a handful of fixed command phrases.
@MainActor
enum CommandMode {
    static func handle(_ text: String, container: ModelContainer?) -> ChatMessage {
        guard let context = container?.mainContext else { return ChatMessage(role: .assistant, text: "Your data isn't open.") }
        let lower = text.lowercased()

        func rest(after prefixes: [String]) -> String? {
            for prefix in prefixes where lower.hasPrefix(prefix) {
                return String(text.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
            }
            return nil
        }

        if lower.contains("next") || lower.contains("what should") || lower.contains("unsure") {
            let ranked = NextUpEngine.rank(in: context)
            guard let top = ranked.first else { return ChatMessage(role: .assistant, text: "You're all caught up. Nice!") }
            var reply = "Do **\(top.title)** next (\(top.detail))."
            if ranked.count > 1 { reply += " After that: \(ranked.dropFirst().prefix(2).map(\.title).joined(separator: ", "))." }
            return ChatMessage(role: .assistant, text: reply)
        }

        if let name = rest(after: ["log ", "done ", "did "]) {
            guard let habit = HubActions.habit(named: name, in: context) else {
                return ChatMessage(role: .assistant, text: "I couldn't find a habit called “\(name)”.")
            }
            HubActions.setHabit(habit, logged: true, in: context)
            return ChatMessage(role: .assistant, text: "Logged \(habit.name). 🔥 \(habit.currentStreak) days.",
                               actions: ["Logged \(habit.name)"])
        }

        if let title = rest(after: ["add task ", "add assignment ", "task ", "todo "]), !title.isEmpty {
            let assignment = HubActions.addAssignment(title: title, due: AssistantDate.tomorrowEvening, in: context)
            return ChatMessage(role: .assistant, text: "Added “\(assignment.title)”, due tomorrow. Adjust the date in Assignments.",
                               actions: ["Added \(assignment.title)"])
        }

        // "spent 12.50 on dining" / "earned 200 from tutoring"
        let words = lower.split(separator: " ").map(String.init)
        if let verb = words.first, ["spent", "earned", "paid"].contains(verb), words.count >= 2,
           let amount = Double(words[1].trimmingCharacters(in: CharacterSet(charactersIn: "$"))) {
            let category = words.count >= 4 ? words[3...].joined(separator: " ").capitalized : ""
            let isIncome = verb == "earned"
            HubActions.addEntry(title: category.isEmpty ? (isIncome ? "Income" : "Expense") : category,
                                amount: amount, isIncome: isIncome,
                                category: category.isEmpty ? (isIncome ? "Income" : "Uncategorized") : category, in: context)
            return ChatMessage(role: .assistant, text: "Recorded \(isIncome ? "+" : "−")\(amount.currency).",
                               actions: ["\(isIncome ? "+" : "−")\(amount.currency) \(category)"])
        }

        if let budgetText = rest(after: ["budget "]) {
            let parts = budgetText.split(separator: " ")
            if let last = parts.last, let limit = Double(last.trimmingCharacters(in: CharacterSet(charactersIn: "$"))), parts.count >= 2 {
                let budget = HubActions.setBudget(category: parts.dropLast().joined(separator: " "), limit: limit, in: context)
                return ChatMessage(role: .assistant, text: "\(budget.name) budget set to \(limit.currency)/month.",
                                   actions: ["\(budget.name) → \(limit.currency)"])
            }
        }

        return ChatMessage(role: .assistant, text: "Try “what next”, “log Workout”, “add task Essay draft”, “spent 12 on Dining”, or “budget Groceries 300”.")
    }
}

struct AssistantView: View {
    @Environment(\.modelContext) private var context
    @State private var model = AssistantModel()
    @State private var draft = ""
    @FocusState private var focused: Bool

    private let starters = ["What should I do next?", "Log my workout", "Add essay due Friday 5pm", "Set dining budget to $150"]

    var body: some View {
        VStack(spacing: 0) {
            if let reason = model.unavailableReason {
                Label(reason, systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(Theme.secondary)
                    .padding(10)
                    .frame(maxWidth: .infinity)
                    .glassEffect(.regular, in: .rect(cornerRadius: 14))
                    .padding(.horizontal, 16)
            }

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(model.messages) { MessageBubble(message: $0).id($0.id) }
                        if model.isThinking {
                            HStack {
                                ProgressView().tint(HubSection.assistant.tint)
                                Text("Thinking…").font(.subheadline).foregroundStyle(Theme.secondary)
                                Spacer()
                            }
                            .id("thinking")
                        }
                    }
                    .padding(16)
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: model.messages.count) {
                    withAnimation { proxy.scrollTo(model.messages.last?.id, anchor: .bottom) }
                }
            }

            if model.messages.count <= 1 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(starters, id: \.self) { starter in
                            Button(starter) { submit(starter) }
                                .font(.subheadline)
                                .buttonStyle(.glass)
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .padding(.bottom, 8)
            }

            HStack(spacing: 10) {
                TextField("Ask or tell me something…", text: $draft, axis: .vertical)
                    .lineLimit(1...4)
                    .focused($focused)
                    .submitLabel(.send)
                    .onSubmit { submit(draft) }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .glassEffect(.regular, in: .capsule)
                Button { submit(draft) } label: {
                    Image(systemName: "arrow.up")
                        .font(.headline.weight(.bold))
                        .frame(width: 46, height: 46)
                }
                .glassEffect(.regular.tint(HubSection.assistant.tint.opacity(0.7)).interactive(), in: .circle)
                .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty || model.isThinking)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
        }
        .background(HubBackground(accent: HubSection.assistant.tint))
        .navigationTitle("Assistant")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("New chat", systemImage: "arrow.counterclockwise") { model.reset() }
            }
        }
        .task { model.configure(container: context.container) }
    }

    private func submit(_ text: String) {
        draft = ""
        Task { await model.send(text) }
    }
}

private struct MessageBubble: View {
    let message: ChatMessage

    var body: some View {
        let isUser = message.role == .user
        HStack {
            if isUser { Spacer(minLength: 50) }
            VStack(alignment: isUser ? .trailing : .leading, spacing: 8) {
                Text(LocalizedStringKey(message.text))
                    .font(.body)
                    .foregroundStyle(isUser ? .black : .white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background {
                        if isUser {
                            RoundedRectangle(cornerRadius: 22).fill(HubSection.assistant.gradient)
                        }
                    }
                    .glassEffect(isUser ? .identity : .regular, in: .rect(cornerRadius: 22))
                ForEach(message.actions, id: \.self) { action in
                    Label(action, systemImage: "checkmark.circle.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.success)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Theme.success.opacity(0.12), in: .capsule)
                }
            }
            if !isUser { Spacer(minLength: 50) }
        }
    }
}
