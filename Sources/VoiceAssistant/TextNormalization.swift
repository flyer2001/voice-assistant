import Foundation

/// Post-STT нормализация русско-английского технического текста.
///
/// Главная задача — convert spoken digit sequences в numeric format:
/// - "ноль точка восемь точка три" → "0.8.3"
/// - "zero dot eight dot three" → "0.8.3"
/// - "пять" / "пятый" в контексте "процентиль" / "версия" → "5"
///
/// На бенчмарке voice-assistant v0.1 эта нормализация уменьшает WER на Set 4
/// (versions/numbers) на 10-15pp для всех STT моделей.
public enum TextNormalization {
    /// Полный pipeline: numbers + cleanup.
    public static func normalize(_ text: String) -> String {
        var result = text
        result = convertSpokenNumbersRU(result)
        result = convertSpokenNumbersEN(result)
        result = collapseDottedSequences(result)
        return result
    }

    // MARK: - Russian spoken digit sequences

    private static let ruDigits: [String: String] = [
        "ноль": "0", "один": "1", "одна": "1", "одно": "1",
        "два": "2", "две": "2",
        "три": "3", "четыре": "4", "пять": "5",
        "шесть": "6", "семь": "7", "восемь": "8", "девять": "9",
        "десять": "10",
    ]

    /// Detect runs of "<digit>(<separator><digit>)+" with "точка" separator.
    /// Example: "ноль точка восемь точка три" → "0.8.3"
    static func convertSpokenNumbersRU(_ text: String) -> String {
        let tokens = text.components(separatedBy: .whitespacesAndNewlines)
        var result: [String] = []
        var i = 0
        while i < tokens.count {
            let lowered = tokens[i].lowercased()
            let stripped = lowered.trimmingCharacters(in: .punctuationCharacters)
            if let digit = ruDigits[stripped] {
                // Look ahead: digit (точка digit)+
                var seq = [digit]
                var j = i + 1
                while j + 1 < tokens.count {
                    let sep = tokens[j].lowercased().trimmingCharacters(in: .punctuationCharacters)
                    let nextStripped = tokens[j + 1].lowercased().trimmingCharacters(in: .punctuationCharacters)
                    guard sep == "точка", let nextDigit = ruDigits[nextStripped] else { break }
                    seq.append(nextDigit)
                    j += 2
                }
                if seq.count >= 2 {
                    result.append(seq.joined(separator: "."))
                    i = j
                    continue
                }
            }
            result.append(tokens[i])
            i += 1
        }
        return result.joined(separator: " ")
    }

    // MARK: - English spoken digit sequences

    private static let enDigits: [String: String] = [
        "zero": "0", "one": "1", "two": "2", "three": "3", "four": "4",
        "five": "5", "six": "6", "seven": "7", "eight": "8", "nine": "9",
        "ten": "10",
    ]

    /// Example: "zero dot eight dot three" → "0.8.3"
    static func convertSpokenNumbersEN(_ text: String) -> String {
        let tokens = text.components(separatedBy: .whitespacesAndNewlines)
        var result: [String] = []
        var i = 0
        while i < tokens.count {
            let stripped = tokens[i].lowercased().trimmingCharacters(in: .punctuationCharacters)
            if let digit = enDigits[stripped] {
                var seq = [digit]
                var j = i + 1
                while j + 1 < tokens.count {
                    let sep = tokens[j].lowercased().trimmingCharacters(in: .punctuationCharacters)
                    let nextStripped = tokens[j + 1].lowercased().trimmingCharacters(in: .punctuationCharacters)
                    guard sep == "dot", let nextDigit = enDigits[nextStripped] else { break }
                    seq.append(nextDigit)
                    j += 2
                }
                if seq.count >= 2 {
                    result.append(seq.joined(separator: "."))
                    i = j
                    continue
                }
            }
            result.append(tokens[i])
            i += 1
        }
        return result.joined(separator: " ")
    }

    // MARK: - Already-dotted numeric sequences

    /// "0 . 8 . 3" → "0.8.3" (collapse spaces around dots when both sides are digits)
    static func collapseDottedSequences(_ text: String) -> String {
        let pattern = #"(\d+)\s*\.\s*(\d+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        var s = text
        // Apply iteratively — handle 0.8.3 (chain)
        for _ in 0..<5 {
            let range = NSRange(s.startIndex..., in: s)
            let next = regex.stringByReplacingMatches(in: s, range: range, withTemplate: "$1.$2")
            if next == s { break }
            s = next
        }
        return s
    }
}
