import SwiftUI

/// Read-only render of a single conversation Turn.
///
/// Plain text for both bubbles; the reply bubble is monospaced so that
/// snippets, paths, and code returned by the assistant land readable.
/// Pending / failure states render distinct treatments so the user can
/// see at a glance whether the round-trip is in flight or broke.
public struct TurnView: View {
    public let turn: Turn

    public init(turn: Turn) {
        self.turn = turn
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            queryBubble
            replyBubble
            timestamp
        }
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var queryBubble: some View {
        Text(turn.query)
            .font(.body)
            .foregroundStyle(.primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var replyBubble: some View {
        switch turn.reply {
        case .pending:
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("…")
                    .font(.body.monospaced())
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
            .frame(maxWidth: .infinity, alignment: .trailing)

        case .success(let reply):
            VStack(alignment: .trailing, spacing: 2) {
                Text(reply.text)
                    .font(.body.monospaced())
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                Text("\(reply.latencyMs) ms")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.blue.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
            .frame(maxWidth: .infinity, alignment: .trailing)

        case .failure(let message):
            Text(message)
                .font(.caption.monospaced())
                .foregroundStyle(.red)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    private var timestamp: some View {
        Text(turn.createdAt.formatted(date: .omitted, time: .standard))
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity, alignment: .center)
    }
}

#Preview("pending") {
    TurnView(turn: Turn(query: "status cashflow"))
        .padding()
}

#Preview("success") {
    var turn = Turn(query: "status cashflow")
    turn.reply = .success(Reply(text: "3 open issues, 2 in progress.", latencyMs: 412))
    return TurnView(turn: turn).padding()
}

#Preview("failure") {
    var turn = Turn(query: "status cashflow")
    turn.reply = .failure("503 backend_unavailable")
    return TurnView(turn: turn).padding()
}
