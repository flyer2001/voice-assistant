import XCTest
@testable import VKAdapter

final class VKEventParserTests: XCTestCase {
    private let parser = VKEventParser()
    private let decoder = JSONDecoder()

    func testParse_textMessage_returnsText() throws {
        let update = try decodeUpdate("""
        {"type":"message_new","group_id":111,"object":{"message":{
          "id":1,"date":1,"peer_id":42,"from_id":42,"text":"привет"
        }}}
        """)

        let source = parser.parse(update)

        XCTAssertEqual(source, .text(peerId: 42, fromId: 42, text: "привет"))
    }

    func testParse_audioMessage_withTranscriptDone_returnsVoiceWithTranscript() throws {
        let update = try decodeUpdate("""
        {"type":"message_new","group_id":111,"object":{"message":{
          "id":1,"date":1,"peer_id":42,"from_id":42,"text":"",
          "attachments":[{"type":"audio_message","audio_message":{
            "id":555,"owner_id":42,"duration":3,
            "link_ogg":"https://cs.vk/x.ogg",
            "transcript":"hi there","transcript_state":"done"
          }}]
        }}}
        """)

        let source = parser.parse(update)

        XCTAssertEqual(source, .voice(
            peerId: 42, fromId: 42,
            linkOgg: "https://cs.vk/x.ogg",
            transcript: "hi there"
        ))
    }

    func testParse_audioMessage_withoutTranscript_returnsVoiceTranscriptNil() throws {
        let update = try decodeUpdate("""
        {"type":"message_new","group_id":111,"object":{"message":{
          "id":1,"date":1,"peer_id":42,"from_id":42,"text":"",
          "attachments":[{"type":"audio_message","audio_message":{
            "id":555,"owner_id":42,"duration":3,
            "link_ogg":"https://cs.vk/x.ogg"
          }}]
        }}}
        """)

        let source = parser.parse(update)

        XCTAssertEqual(source, .voice(
            peerId: 42, fromId: 42,
            linkOgg: "https://cs.vk/x.ogg",
            transcript: nil
        ))
    }

    func testParse_audioMessage_transcriptStateError_returnsVoiceTranscriptNil() throws {
        let update = try decodeUpdate("""
        {"type":"message_new","group_id":111,"object":{"message":{
          "id":1,"date":1,"peer_id":42,"from_id":42,"text":"",
          "attachments":[{"type":"audio_message","audio_message":{
            "id":555,"owner_id":42,"duration":3,
            "link_ogg":"https://cs.vk/x.ogg",
            "transcript":"partial garbled","transcript_state":"error"
          }}]
        }}}
        """)

        let source = parser.parse(update)

        XCTAssertEqual(source, .voice(
            peerId: 42, fromId: 42,
            linkOgg: "https://cs.vk/x.ogg",
            transcript: nil
        ))
    }

    func testParse_audioPlusText_prioritizesVoice() throws {
        // Реальный VK кейс: пользователь записал voice + добавил caption.
        // Voice — primary intent, текст игнорируем (или будет logged).
        let update = try decodeUpdate("""
        {"type":"message_new","group_id":111,"object":{"message":{
          "id":1,"date":1,"peer_id":42,"from_id":42,"text":"caption",
          "attachments":[{"type":"audio_message","audio_message":{
            "id":555,"owner_id":42,"duration":3,
            "link_ogg":"https://cs.vk/x.ogg",
            "transcript":"voice transcript","transcript_state":"done"
          }}]
        }}}
        """)

        let source = parser.parse(update)

        XCTAssertEqual(source, .voice(
            peerId: 42, fromId: 42,
            linkOgg: "https://cs.vk/x.ogg",
            transcript: "voice transcript"
        ))
    }

    func testParse_nonMessageNewType_returnsIgnoredUnsupported() throws {
        let update = try decodeUpdate("""
        {"type":"message_reply","group_id":111,"object":{"message":{
          "id":1,"date":1,"peer_id":42,"from_id":42,"text":"ok"
        }}}
        """)

        let source = parser.parse(update)

        XCTAssertEqual(source, .ignored(.unsupportedType("message_reply")))
    }

    func testParse_messageNewEmptyTextNoAttachments_returnsIgnoredEmpty() throws {
        let update = try decodeUpdate("""
        {"type":"message_new","group_id":111,"object":{"message":{
          "id":1,"date":1,"peer_id":42,"from_id":42,"text":""
        }}}
        """)

        let source = parser.parse(update)

        XCTAssertEqual(source, .ignored(.emptyContent))
    }

    func testParse_messageNewNoMessageObject_returnsIgnoredNoMessage() throws {
        let update = try decodeUpdate("""
        {"type":"message_new","group_id":111,"object":{}}
        """)

        let source = parser.parse(update)

        XCTAssertEqual(source, .ignored(.noMessage))
    }

    func testParse_audioMessageWithNonAudioAttachmentMixed_picksAudio() throws {
        // Audio + photo attachment в одном сообщении — voice всё равно primary.
        let update = try decodeUpdate("""
        {"type":"message_new","group_id":111,"object":{"message":{
          "id":1,"date":1,"peer_id":42,"from_id":42,"text":"",
          "attachments":[
            {"type":"photo"},
            {"type":"audio_message","audio_message":{
              "id":555,"owner_id":42,"duration":3,
              "link_ogg":"https://cs.vk/x.ogg"
            }}
          ]
        }}}
        """)

        let source = parser.parse(update)

        XCTAssertEqual(source, .voice(
            peerId: 42, fromId: 42,
            linkOgg: "https://cs.vk/x.ogg",
            transcript: nil
        ))
    }

    // MARK: - Helpers

    private func decodeUpdate(_ json: String) throws -> VKUpdate {
        try decoder.decode(VKUpdate.self, from: Data(json.utf8))
    }
}
