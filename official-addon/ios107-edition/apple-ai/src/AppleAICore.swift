import Foundation

func taiIsHan(_ scalar: Unicode.Scalar) -> Bool {
    (0x3400...0x4DBF).contains(scalar.value) || (0x4E00...0x9FFF).contains(scalar.value) || (0xF900...0xFAFF).contains(scalar.value)
}
func taiHanCount(_ text: String) -> Int { text.unicodeScalars.filter(taiIsHan).count }
func taiLanguage(_ text: String) -> String {
    let han = taiHanCount(text)
    let ascii = text.unicodeScalars.filter { (65...90).contains($0.value) || (97...122).contains($0.value) }.count
    return han > 0 && han * 4 >= ascii ? "zh" : "en"
}
func taiEstimateTokens(_ text: String) -> Int {
    let other = text.unicodeScalars.filter { !taiIsHan($0) && !CharacterSet.whitespacesAndNewlines.contains($0) }.count
    return taiHanCount(text) + (other + 2) / 3 + 4
}
func taiResponseReserve(contextSize: Int) -> Int { min(600, max(200, contextSize / 5)) }
func taiHistoryBudget(contextSize: Int, instructionsTokens: Int, promptTokens: Int, reserve: Int) -> Int {
    max(0, contextSize - instructionsTokens - promptTokens - reserve - 64)
}
func taiHistoryPairs(_ rows: [[String: String]]) -> [(q: String, a: String)] {
    var pairs: [(q: String, a: String)] = []
    for (index, row) in rows.enumerated() {
        guard row["role"] == (index % 2 == 0 ? "user" : "assistant"),
              let content = row["content"], !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }
        if index % 2 == 1 { pairs.append((rows[index - 1]["content"]!, content)) }
    }
    return pairs
}
func taiTrimHistory(_ pairs: [(q: String, a: String)], budget: Int, count: (String) -> Int) -> [(q: String, a: String)] {
    var kept: [(q: String, a: String)] = [], used = 0
    for pair in pairs.reversed() {
        let cost = count(pair.q) + count(pair.a)
        guard used + cost <= budget else { break }
        used += cost; kept.append(pair)
    }
    return kept.reversed()
}
struct TAIPrefixStream {
    private(set) var emitted = ""
    mutating func accept(_ snapshot: String) -> String? {
        guard snapshot.count > emitted.count, snapshot.hasPrefix(emitted) else { return nil }
        emitted = snapshot; return snapshot
    }
    mutating func finish(_ text: String) -> String {
        if text.hasPrefix(emitted) { emitted = text }
        return emitted
    }
}
func taiTimestamp(_ seconds: Double) -> String {
    guard seconds.isFinite, seconds >= 0, seconds < Double(Int.max) else { return "[00:00]" }
    let value = Int(seconds)
    if value >= 3600 { return String(format: "[%d:%02d:%02d]", value / 3600, value / 60 % 60, value % 60) }
    return String(format: "[%02d:%02d]", value / 60, value % 60)
}
func taiTranscriptMarkdown(_ segments: [(start: Double, text: String)]) -> String {
    segments.compactMap { segment in
        let text = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : taiTimestamp(segment.start) + " " + text
    }.joined(separator: "\n")
}
func taiTail(_ text: String, bytes: Int) -> String {
    var result = "", used = 0
    for character in text.reversed() {
        let value = String(character), size = value.utf8.count
        guard used + size <= bytes else { break }
        result = value + result; used += size
    }
    return result
}
func taiCaptionDisplay(source: String, translated: String, sourceLabel: String, targetLabel: String, preview: Bool) -> String {
    if translated.isEmpty { return taiTail(source, bytes: 360) }
    // Labels normally are EN and 中; bound them as well to preserve the wire cap.
    return taiTail(sourceLabel, bytes: 12) + ": " + taiTail(source, bytes: 130) + "\n" +
        taiTail(targetLabel, bytes: 12) + (preview ? "…" : "") + ": " + taiTail(translated, bytes: 210)
}
enum TAIL10n {
    private static let lock = NSLock()
    private static var code = "en"
    static var language: String {
        get { lock.lock(); defer { lock.unlock() }; return code }
        set { lock.lock(); defer { lock.unlock() }; code = newValue.hasPrefix("zh") ? "zh" : "en" }
    }
    static func t(_ en: String, _ zh: String) -> String { language == "zh" ? zh : en }
}
