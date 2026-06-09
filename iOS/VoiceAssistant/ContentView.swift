import SwiftUI
import VoiceAssistant

struct ContentView: View {
    @StateObject private var runner = BenchRunner()

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Text("Voice Assistant")
                    .font(.largeTitle)
                    .bold()
                Text("STT bench skeleton — v0.1")
                    .foregroundStyle(.secondary)

                Button(action: { Task { await runner.runAll() } }) {
                    Label(runner.isRunning ? "Running…" : "Run benchmark",
                          systemImage: runner.isRunning ? "hourglass" : "play.fill")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(runner.isRunning ? Color.gray : Color.accentColor)
                        .foregroundColor(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .disabled(runner.isRunning)
                .padding(.horizontal)

                ScrollView {
                    Text(runner.log)
                        .font(.system(.caption, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                        .background(Color(.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .padding(.horizontal)

                Spacer()
            }
            .padding(.top)
        }
    }
}

#Preview {
    ContentView()
}
