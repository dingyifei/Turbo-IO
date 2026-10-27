import Foundation

@main struct AppleAICoreTests {
    static func main() {
        precondition(taiHanCount("你好㐀豈A🙂") == 4)
        for (text, language) in [("你好", "zh"), ("Hello world", "en"), ("用 Swift 写一个 app", "zh"), ("What does 你好 mean in English", "en")] {
            precondition(taiLanguage(text) == language)
        }
        precondition(taiEstimateTokens("你好 abc") == 7)
        precondition(taiResponseReserve(contextSize: 4096) == 600)
        precondition(taiResponseReserve(contextSize: 100) == 200)
        precondition(taiHistoryBudget(contextSize: 1000, instructionsTokens: 100, promptTokens: 100, reserve: 200) == 536)
        precondition(taiHistoryBudget(contextSize: 100, instructionsTokens: 100, promptTokens: 100, reserve: 200) == 0)
        let rows = [["role":"user", "content":"old"], ["role":"assistant", "content":"answer"], ["role":"user", "content":"new"], ["role":"assistant", "content":"reply"], ["role":"user", "content":"pending"]]
        let pairs = taiHistoryPairs(rows)
        precondition(pairs.count == 2)
        precondition(taiHistoryPairs([["role":"assistant", "content":"bad"]]).isEmpty)
        precondition(taiHistoryPairs([["role":"user", "content":" "]]).isEmpty)
        let trimmed = taiTrimHistory(pairs, budget: 8, count: { $0.count })
        precondition(trimmed.count == 1 && trimmed[0].q == "new")
        precondition(taiTrimHistory(pairs, budget: 100, count: { $0.count }).map(\.q) == ["old", "new"])
        var prefix = TAIPrefixStream()
        precondition(prefix.accept("Hello") == "Hello")
        precondition(prefix.accept("Help") == nil)
        precondition(prefix.accept("Hello") == nil)
        precondition(prefix.accept("Hello world") == "Hello world")
        precondition(prefix.finish("rewrite") == "Hello world")
        precondition(taiTimestamp(.nan) == "[00:00]")
        precondition(taiTimestamp(-1) == "[00:00]")
        precondition(taiTimestamp(65.9) == "[01:05]")
        precondition(taiTimestamp(3601) == "[1:00:01]")
        precondition(taiTranscriptMarkdown([(0," hi "), (3,"  "), (65,"你好")]) == "[00:00] hi\n[01:05] 你好")
        precondition(taiTail("a🙂中", bytes: 7) == "🙂中")
        precondition(taiTail("🙂", bytes: 3).isEmpty)
        precondition(taiTail("abc", bytes: -1).isEmpty)
        let huge = String(repeating: "中🙂", count: 200)
        precondition(taiCaptionDisplay(source: huge, translated: "", sourceLabel: "EN", targetLabel: "中", preview: false).utf8.count <= 360)
        precondition(taiCaptionDisplay(source: huge, translated: huge, sourceLabel: "EN", targetLabel: "中", preview: true).utf8.count <= 384)
        precondition(taiCaptionDisplay(source: huge, translated: huge, sourceLabel: huge, targetLabel: huge, preview: true).utf8.count <= 384)
        TAIL10n.language = "zh"
        precondition(TAIL10n.t("Hello", "你好") == "你好")
        TAIL10n.language = "en"
        precondition(TAIL10n.t("Hello", "你好") == "Hello")
        print("PASS apple-ai core")
    }
}
