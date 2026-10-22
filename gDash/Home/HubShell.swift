import SwiftUI

/// Navigation container: the home menu at the root, each section pushed on top.
struct HubShell: View {
    @State private var path: [HubSection] = []
    @State private var showAssistant = false

    var body: some View {
        NavigationStack(path: $path) {
            HomeView(path: $path)
                .navigationDestination(for: HubSection.self) { section in
                    switch section {
                    case .assignments: AssignmentsView()
                    case .calendar: ScheduleView()
                    case .habits: HabitsView()
                    case .finances: FinancesView()
                    case .assistant: AssistantView()
                    }
                }
        }
        .overlay(alignment: .bottomTrailing) {
            if path.isEmpty {
                Button { showAssistant = true } label: {
                    Image(systemName: "sparkles")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 62, height: 62)
                }
                .glassEffect(.regular.tint(HubSection.assistant.tint.opacity(0.55)).interactive(), in: .circle)
                .padding(22)
                .transition(.scale.combined(with: .opacity))
                .accessibilityLabel("Open assistant")
            }
        }
        .animation(.spring(response: 0.4), value: path.isEmpty)
        .sheet(isPresented: $showAssistant) {
            NavigationStack { AssistantView() }
                .presentationDetents([.medium, .large])
        }
    }
}
