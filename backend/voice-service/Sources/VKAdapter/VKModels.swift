import Foundation

public struct VKAPIResponse<T: Decodable & Sendable>: Decodable, Sendable {
    public let response: T?
    public let error: VKAPIError?
}

public struct VKAPIError: Decodable, Sendable, CustomStringConvertible, Equatable, Error {
    public let errorCode: Int
    public let errorMsg: String

    enum CodingKeys: String, CodingKey {
        case errorCode = "error_code"
        case errorMsg = "error_msg"
    }

    public var description: String {
        "VK API error \(errorCode): \(errorMsg)"
    }
}

public typealias VKMessageSendResult = Int64

public struct VKLongPollServer: Decodable, Sendable, Equatable {
    public let server: String
    public let key: String
    public let ts: String
}

public struct VKLongPollUpdates: Decodable, Sendable {
    public let ts: String?
    public let updates: [VKUpdate]?
    public let failed: Int?
}

public struct VKUpdate: Decodable, Sendable {
    public let type: String
    public let object: VKObject?
    public let groupId: Int?

    enum CodingKeys: String, CodingKey {
        case type, object
        case groupId = "group_id"
    }
}

public struct VKObject: Decodable, Sendable {
    public let message: VKMessage?
}

public struct VKMessage: Decodable, Sendable, Equatable {
    public let id: Int64
    public let date: Int64
    public let peerId: Int64
    public let fromId: Int64
    public let text: String
    public let attachments: [VKAttachment]?

    enum CodingKeys: String, CodingKey {
        case id, date, text, attachments
        case peerId = "peer_id"
        case fromId = "from_id"
    }
}

public struct VKAttachment: Decodable, Sendable, Equatable {
    public let type: String
    public let audioMessage: VKAudioMessage?

    enum CodingKeys: String, CodingKey {
        case type
        case audioMessage = "audio_message"
    }
}

public struct VKAudioMessage: Decodable, Sendable, Equatable {
    public let id: Int64
    public let ownerId: Int64
    public let duration: Int
    public let linkOgg: String
    public let linkMp3: String?
    public let accessKey: String?
    public let transcript: String?
    public let transcriptState: String?

    enum CodingKeys: String, CodingKey {
        case id, duration, transcript
        case ownerId = "owner_id"
        case linkOgg = "link_ogg"
        case linkMp3 = "link_mp3"
        case accessKey = "access_key"
        case transcriptState = "transcript_state"
    }
}

public struct VKDocsUploadServer: Decodable, Sendable, Equatable {
    public let uploadUrl: String

    enum CodingKeys: String, CodingKey {
        case uploadUrl = "upload_url"
    }
}

public struct VKDocsUploadResult: Decodable, Sendable, Equatable {
    public let file: String
}

public struct VKDocsSaveResult: Decodable, Sendable, Equatable {
    public let type: String
    public let audioMessage: VKSavedAudioMessage?

    enum CodingKeys: String, CodingKey {
        case type
        case audioMessage = "audio_message"
    }
}

public struct VKSavedAudioMessage: Decodable, Sendable, Equatable {
    public let id: Int64
    public let ownerId: Int64

    enum CodingKeys: String, CodingKey {
        case id
        case ownerId = "owner_id"
    }
}
