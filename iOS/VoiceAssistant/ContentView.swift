import SwiftUI
import UIKit

struct ContentView: View {
    @State private var state: RecordingState = .idle
    @State private var lastTurn: String = ""
    @State private var lastTrigger: TriggerSource = .none

    var body: some View {
        VStack(spacing: 0) {
            header

            Spacer()

            holdButton
                .frame(width: 240, height: 240)
                .gesture(holdGesture)

            Text(state.label)
                .font(.title3)
                .foregroundStyle(state.tint)
                .padding(.top, 24)
                .animation(.easeInOut(duration: 0.15), value: state)

            Spacer()

            footer
        }
        .padding()
        .background(
            KeyMonitor(
                onKeyDown: { (code: UIKeyboardHIDUsage) in
                    guard code == .keyboardF15, state == .idle else { return }
                    lastTrigger = .keyboard
                    state = .recording
                },
                onKeyUp: { (code: UIKeyboardHIDUsage) in
                    guard code == .keyboardF15, state == .recording else { return }
                    finishRecording()
                }
            )
        )
    }

    private var header: some View {
        VStack(spacing: 4) {
            Text("Voice Assistant")
                .font(.title2.weight(.semibold))
            Text("v0.1 — hold-to-speak")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var holdButton: some View {
        ZStack {
            Circle()
                .fill(state.tint.opacity(state == .recording ? 0.25 : 0.12))
            Circle()
                .stroke(state.tint, lineWidth: state == .recording ? 4 : 2)
            Image(systemName: state.symbol)
                .font(.system(size: 72, weight: .regular))
                .foregroundStyle(state.tint)
                .symbolEffect(.pulse, options: .repeating, isActive: state == .recording)
        }
        .scaleEffect(state == .recording ? 1.05 : 1.0)
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: state)
    }

    private var footer: some View {
        VStack(spacing: 4) {
            Text(lastTurn.isEmpty ? "no turns yet" : lastTurn)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, minHeight: 32, alignment: .center)
            Text("bind: touch + F15")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    private var holdGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { _ in
                guard state == .idle else { return }
                lastTrigger = .touch
                state = .recording
            }
            .onEnded { _ in
                guard state == .recording else { return }
                finishRecording()
            }
    }

    private func finishRecording() {
        state = .processing
        let trigger = lastTrigger
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1))
            lastTurn = "[\(trigger.label)] processed at \(Date.now.formatted(date: .omitted, time: .standard))"
            state = .idle
            lastTrigger = .none
        }
    }
}

enum TriggerSource {
    case none, touch, keyboard
    var label: String {
        switch self {
        case .none:     return "—"
        case .touch:    return "touch"
        case .keyboard: return "F15"
        }
    }
}

enum RecordingState: Equatable {
    case idle
    case recording
    case processing

    var label: String {
        switch self {
        case .idle:       return "Hold to speak"
        case .recording:  return "Recording…"
        case .processing: return "Processing…"
        }
    }

    var symbol: String {
        switch self {
        case .idle:       return "mic"
        case .recording:  return "waveform"
        case .processing: return "ellipsis"
        }
    }

    var tint: Color {
        switch self {
        case .idle:       return .secondary
        case .recording:  return .red
        case .processing: return .orange
        }
    }
}

#Preview {
    ContentView()
}
