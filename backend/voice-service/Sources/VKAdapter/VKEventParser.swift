import Foundation

public enum VKIntentSource: Equatable, Sendable {
    case text(peerId: Int64, fromId: Int64, text: String)
    case voice(peerId: Int64, fromId: Int64, linkOgg: String, transcript: String?)
    case ignored(VKIntentIgnoreReason)
}

public enum VKIntentIgnoreReason: Equatable, Sendable {
    case unsupportedType(String)
    case noMessage
    case emptyContent
}

public struct VKEventParser: Sendable {
    public init() {}

    public func parse(_ update: VKUpdate) -> VKIntentSource {
        guard update.type == "message_new" else {
            return .ignored(.unsupportedType(update.type))
        }
        guard let message = update.object?.message else {
            return .ignored(.noMessage)
        }

        if let audio = message.attachments?.compactMap({ $0.audioMessage }).first {
            let transcript: String? = audio.transcriptState == "done" ? audio.transcript : nil
            return .voice(
                peerId: message.peerId,
                fromId: message.fromId,
                linkOgg: audio.linkOgg,
                transcript: transcript
            )
        }

        if !message.text.isEmpty {
            return .text(peerId: message.peerId, fromId: message.fromId, text: message.text)
        }

        return .ignored(.emptyContent)
    }
}
