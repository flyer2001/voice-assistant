import SwiftUI
import VoiceAssistant

struct ContentView: View {
    @StateObject private var runner = BenchRunner()

    var body: some View {
        VStack(spacing: 12) {
            Text("Voice Assistant")
                .font(.largeTitle)
                .bold()
            Text("Bench — autostart on launch")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack {
                if runner.isRunning {
                    ProgressView()
                    Text("Running…").foregroundStyle(.secondary)
                } else if runner.log_ui.contains("=== DONE ===") {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    Text("Done").foregroundStyle(.green)
                } else {
                    Image(systemName: "circle.dashed").foregroundStyle(.secondary)
                    Text("Initializing…").foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)

            ScrollView {
                Text(runner.log_ui.isEmpty ? "Bench starting…" : runner.log_ui)
                    .font(.system(.caption, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .padding(.horizontal)
        }
        .padding()
        .onAppear {
            Task { await runner.runAll() }
        }
    }
}

#Preview {
    ContentView()
}
