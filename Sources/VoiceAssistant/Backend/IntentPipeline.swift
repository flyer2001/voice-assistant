import Foundation

/// Glues transcript → BackendAdapter → TurnsStore. ContentView holds
/// one of these per session; it calls `handle` after STT finishes and
/// the UI re-renders via TurnsStore's @Observable conformance.
///
/// `handle` appends a pending turn FIRST so the UI shows the user-side
/// of the conversation immediately, then awaits the reply and patches
/// the same turn in place (.success / .failure). The error path is
/// labelled here, not at the UI layer, so any future client (macOS,
/// Watch) gets the same wording without duplicating the switch.
public final class IntentPipeline {
    private let dispatcher: any BackendAdapter
    private let store: TurnsStore

    public init(dispatcher: any BackendAdapter, store: TurnsStore) {
        self.dispatcher = dispatcher
        self.store = store
    }

    public func handle(transcript: String, clientId: String) async {
        let turn = Turn(query: transcript)
        store.append(turn)

        do {
            let reply = try await dispatcher.send(
                TranscribedRequest(text: transcript, clientId: clientId)
            )
            store.updateReply(id: turn.id, to: .success(reply))
        } catch let error as BackendError {
            store.updateReply(id: turn.id, to: .failure(Self.label(for: error)))
        } catch {
            store.updateReply(id: turn.id, to: .failure("unexpected: \(error)"))
        }
    }

    public static func label(for error: BackendError) -> String {
        switch error {
        case .unauthorized:
            return "401 unauthorized"
        case .forbidden:
            return "403 forbidden"
        case .rateLimited(let retryAfterMs):
            return "429 rate_limited (retry \(retryAfterMs ?? 0) ms)"
        case .backendUnavailable:
            return "503 backend_unavailable"
        case .timeout:
            return "timeout"
        case .network(let underlying):
            return "network: \(underlying)"
        case .malformedResponse(let message):
            return "malformed: \(message)"
        }
    }
}
