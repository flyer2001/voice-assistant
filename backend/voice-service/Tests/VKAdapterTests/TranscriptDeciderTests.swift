import XCTest
@testable import VKAdapter

final class TranscriptDeciderTests: XCTestCase {
    func test_stateDoneWithText_picksVK() {
        XCTAssertEqual(
            TranscriptDecider.decide(transcript: "привет", transcriptState: "done"),
            .useVK("привет")
        )
    }

    func test_stateDoneEmpty_picksWhisper() {
        XCTAssertEqual(
            TranscriptDecider.decide(transcript: "", transcriptState: "done"),
            .useWhisper
        )
    }

    func test_stateInProgress_picksWhisper() {
        XCTAssertEqual(
            TranscriptDecider.decide(transcript: nil, transcriptState: "in_progress"),
            .useWhisper
        )
    }

    func test_stateError_picksWhisper() {
        XCTAssertEqual(
            TranscriptDecider.decide(transcript: "garbage", transcriptState: "error"),
            .useWhisper
        )
    }

    func test_stateAbsent_picksWhisper() {
        XCTAssertEqual(
            TranscriptDecider.decide(transcript: nil, transcriptState: nil),
            .useWhisper
        )
    }
}
