import XCTest
@testable import VoiceAssistant

final class TextNormalizationTests: XCTestCase {

    // MARK: - RU spoken digits

    func test_RU_version_triple() {
        let input = "Обнови WhisperKit до версии ноль точка восемь точка три."
        let out = TextNormalization.normalize(input)
        XCTAssertTrue(out.contains("0.8.3"), "expected '0.8.3' in '\(out)'")
    }

    func test_RU_simple_pair() {
        XCTAssertEqual(
            TextNormalization.normalize("два точка пять"),
            "2.5"
        )
    }

    func test_RU_single_digit_not_converted() {
        // "семь" один не должен превращаться в "7" — это просто слово
        let input = "около семи часов"
        let out = TextNormalization.normalize(input)
        XCTAssertEqual(out, input)
    }

    // MARK: - EN spoken digits

    func test_EN_version_triple() {
        let input = "update WhisperKit to zero dot eight dot three"
        let out = TextNormalization.normalize(input)
        XCTAssertTrue(out.contains("0.8.3"), "expected '0.8.3' in '\(out)'")
    }

    func test_EN_simple_pair() {
        XCTAssertEqual(
            TextNormalization.normalize("five dot zero"),
            "5.0"
        )
    }

    // MARK: - Already-dotted sequences

    func test_collapse_spaced_dotted() {
        XCTAssertEqual(
            TextNormalization.normalize("0 . 8 . 3"),
            "0.8.3"
        )
    }

    func test_collapse_mixed_runs() {
        // Whisper иногда даёт "0.8 . 3"
        XCTAssertEqual(
            TextNormalization.normalize("0.8 . 3"),
            "0.8.3"
        )
    }

    // MARK: - Full corpus simulation

    func test_full_4b_corpus() {
        let input = "В Package.swift обнови WhisperKit до версии ноль точка восемь точка три, перезапусти build через swift build, и если зелёный — закомить с сообщением update WhisperKit to zero dot eight dot three."
        let out = TextNormalization.normalize(input)
        // Должно появиться "0.8.3" дважды (русская часть + английская)
        let occurrences = out.components(separatedBy: "0.8.3").count - 1
        XCTAssertEqual(occurrences, 2, "expected 0.8.3 twice in normalized output: '\(out)'")
    }

    func test_no_false_positives_clean_RU() {
        // Set 1 — clean Russian, никаких чисел не должно появиться
        let input = "Сегодня вторник нужно успеть в магазин купить молоко хлеб помидоры и заехать на заправку"
        XCTAssertEqual(TextNormalization.normalize(input), input)
    }
}
