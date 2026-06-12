import XCTest
@testable import VKAdapter

final class VKModelsTests: XCTestCase {
    private let decoder = JSONDecoder()

    func testDecodeLongPollServer() throws {
        let json = """
        {"response":{"server":"https://lp.vk.com/wh123","key":"abc","ts":"42"}}
        """.data(using: .utf8)!

        let resp = try decoder.decode(VKAPIResponse<VKLongPollServer>.self, from: json)

        XCTAssertEqual(resp.response, VKLongPollServer(server: "https://lp.vk.com/wh123", key: "abc", ts: "42"))
        XCTAssertNil(resp.error)
    }

    func testDecodeAPIError() throws {
        let json = """
        {"error":{"error_code":100,"error_msg":"missing parameter"}}
        """.data(using: .utf8)!

        let resp = try decoder.decode(VKAPIResponse<VKLongPollServer>.self, from: json)

        XCTAssertNil(resp.response)
        XCTAssertEqual(resp.error, VKAPIError(errorCode: 100, errorMsg: "missing parameter"))
    }

    func testDecodeLongPollUpdates_textMessage() throws {
        let json = """
        {
          "ts":"43",
          "updates":[
            {
              "type":"message_new",
              "group_id":111,
              "object":{
                "message":{
                  "id":7,"date":1,"peer_id":42,"from_id":42,"text":"hi"
                }
              }
            }
          ]
        }
        """.data(using: .utf8)!

        let updates = try decoder.decode(VKLongPollUpdates.self, from: json)

        XCTAssertEqual(updates.ts, "43")
        XCTAssertNil(updates.failed)
        let event = try XCTUnwrap(updates.updates?.first)
        XCTAssertEqual(event.type, "message_new")
        XCTAssertEqual(event.groupId, 111)
        let msg = try XCTUnwrap(event.object?.message)
        XCTAssertEqual(msg.text, "hi")
        XCTAssertEqual(msg.peerId, 42)
        XCTAssertNil(msg.attachments)
    }

    func testDecodeLongPollUpdates_failed() throws {
        let json = #"{"failed":1,"ts":"99"}"#.data(using: .utf8)!

        let updates = try decoder.decode(VKLongPollUpdates.self, from: json)

        XCTAssertEqual(updates.failed, 1)
        XCTAssertEqual(updates.ts, "99")
    }

    func testDecodeAudioMessageAttachment_withTranscript() throws {
        let json = """
        {
          "id":1,"date":1,"peer_id":42,"from_id":42,"text":"",
          "attachments":[
            {
              "type":"audio_message",
              "audio_message":{
                "id":555,"owner_id":42,"duration":3,
                "link_ogg":"https://cs.vk/x.ogg",
                "link_mp3":"https://cs.vk/x.mp3",
                "access_key":"k",
                "transcript":"привет",
                "transcript_state":"done"
              }
            }
          ]
        }
        """.data(using: .utf8)!

        let msg = try decoder.decode(VKMessage.self, from: json)

        let att = try XCTUnwrap(msg.attachments?.first)
        XCTAssertEqual(att.type, "audio_message")
        let audio = try XCTUnwrap(att.audioMessage)
        XCTAssertEqual(audio.id, 555)
        XCTAssertEqual(audio.ownerId, 42)
        XCTAssertEqual(audio.duration, 3)
        XCTAssertEqual(audio.linkOgg, "https://cs.vk/x.ogg")
        XCTAssertEqual(audio.transcript, "привет")
        XCTAssertEqual(audio.transcriptState, "done")
    }

    func testDecodeAudioMessageAttachment_noTranscript() throws {
        let json = """
        {
          "id":1,"date":1,"peer_id":42,"from_id":42,"text":"",
          "attachments":[
            {
              "type":"audio_message",
              "audio_message":{
                "id":555,"owner_id":42,"duration":3,
                "link_ogg":"https://cs.vk/x.ogg"
              }
            }
          ]
        }
        """.data(using: .utf8)!

        let msg = try decoder.decode(VKMessage.self, from: json)

        let audio = try XCTUnwrap(msg.attachments?.first?.audioMessage)
        XCTAssertNil(audio.transcript)
        XCTAssertNil(audio.transcriptState)
    }

    func testDecodeDocsGetUploadServer() throws {
        let json = """
        {"response":{"upload_url":"https://pu.vk.com/?act=add_doc&abc"}}
        """.data(using: .utf8)!

        let resp = try decoder.decode(VKAPIResponse<VKDocsUploadServer>.self, from: json)
        XCTAssertEqual(resp.response?.uploadUrl, "https://pu.vk.com/?act=add_doc&abc")
    }

    func testDecodeDocsUploadResult() throws {
        let json = #"{"file":"opaque-string-from-vk"}"#.data(using: .utf8)!
        let result = try decoder.decode(VKDocsUploadResult.self, from: json)
        XCTAssertEqual(result.file, "opaque-string-from-vk")
    }

    func testDecodeDocsSave_audioMessage() throws {
        let json = """
        {"response":[{"type":"audio_message","audio_message":{"id":777,"owner_id":-222}}]}
        """.data(using: .utf8)!

        let resp = try decoder.decode(VKAPIResponse<[VKDocsSaveResult]>.self, from: json)

        let first = try XCTUnwrap(resp.response?.first)
        XCTAssertEqual(first.type, "audio_message")
        XCTAssertEqual(first.audioMessage, VKSavedAudioMessage(id: 777, ownerId: -222))
    }
}
