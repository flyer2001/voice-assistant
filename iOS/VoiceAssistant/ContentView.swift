import SwiftUI
import UIKit
import VoiceAssistant

struct ContentView: View {
    @State private var state: RecordingState = .idle
    @State private var lastTurn: String = ""
    @State private var lastTrigger: TriggerSource = .none
    @State private var capture: AudioCapture = LiveAudioCapture()
    @State private var uploader: STTUploader = LiveSTTUploader(
        // Dev default: backend running on the mac-home host of the simulator.
        // iOS Simulator routes localhost to its host. Real device / production
        // overrides via secrets.local or Keychain (C8 ticket).
        baseURL: URL(string: "http://127.0.0.1:8089")!,
        token: "dev-token"
    )
    private let clientId = "iphone-sim-dev"

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
                    beginRecording(trigger: .keyboard)
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
            Text("bind: touch + F15  ·  upload: 127.0.0.1:8089")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    private var holdGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { _ in
                guard state == .idle else { return }
                beginRecording(trigger: .touch)
            }
            .onEnded { _ in
                guard state == .recording else { return }
                finishRecording()
            }
    }

    private func beginRecording(trigger: TriggerSource) {
        lastTrigger = trigger
        state = .recording
        Task { @MainActor in
            do {
                try await capture.start()
            } catch {
                lastTurn = "[\(trigger.label)] start failed: \(error)"
                state = .idle
                lastTrigger = .none
            }
        }
    }

    private func finishRecording() {
        state = .processing
        let trigger = lastTrigger
        Task { @MainActor in
            let captureResult: (url: URL, bytes: Data)?
            do {
                let url = try await capture.stop()
                let bytes = try Data(contentsOf: url)
                captureResult = (url, bytes)
            } catch {
                lastTurn = "[\(trigger.label)] capture failed: \(error)"
                state = .idle
                lastTrigger = .none
                return
            }
            guard let (_, bytes) = captureResult else {
                state = .idle; lastTrigger = .none; return
            }
            do {
                let response = try await uploader.upload(
                    audio: bytes,
                    clientId: clientId,
                    ts: .now
                )
                lastTurn = "[\(trigger.label)] \(response.text)"
            } catch let error as STTUploaderError {
                lastTurn = "[\(trigger.label)] upload err: \(label(for: error))"
            } catch {
                lastTurn = "[\(trigger.label)] upload err: \(error)"
            }
            state = .idle
            lastTrigger = .none
        }
    }

    private func label(for error: STTUploaderError) -> String {
        switch error {
        case .unauthorized:       return "401 unauthorized"
        case .unsupportedFormat:  return "400 unsupported_format"
        case .audioTooShort:      return "400 audio_too_short"
        case .audioTooLong:       return "400 audio_too_long"
        case .sttUnavailable:     return "503 stt_unavailable"
        case .sttTimeout:         return "504 stt_timeout"
        case .backendUnavailable: return "5xx backend_unavailable"
        case .network(let msg):   return "network: \(msg)"
        case .malformedResponse(let m): return "malformed: \(m)"
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
