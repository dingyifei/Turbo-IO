import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

@available(iOS 26.0, *)
@objc(TIOAppleLLMTask) public final class AppleLLMTask: NSObject {
    private let lock = NSLock()
    private var stopped = false
    private var work: Task<Void, Never>?
    var lifecycle: TAIResponseLifecycle?
    func supersede() { lifecycle?.supersede(); cancel() }
    var cancelled: Bool { lock.lock(); defer { lock.unlock() }; return stopped }
    func install(_ task: Task<Void, Never>) { lock.lock(); work = task; let stop = stopped; lock.unlock(); if stop { task.cancel() } }
    @objc public func cancel() {
        if !Thread.isMainThread { DispatchQueue.main.sync { self.cancel() }; return }
        lifecycle?.cancel()
        lock.lock(); stopped = true; let task = work; work = nil; lock.unlock(); task?.cancel() }
}

@available(iOS 26.0, *)
@objc(TIOAppleLLM) public final class AppleLLM: NSObject {
    // All accesses occur on the main queue, including calls from Objective-C.
    private static var current: AppleLLMTask?
    @objc(availability) public static func availability() -> NSDictionary {
        #if canImport(FoundationModels)
        let model = SystemLanguageModel.default
        var reason = "available", available = false
        switch model.availability {
        case .available: available = true
        case .unavailable(let value):
            switch value {
            case .deviceNotEligible: reason = "deviceNotEligible"
            case .appleIntelligenceNotEnabled: reason = "appleIntelligenceNotEnabled"
            case .modelNotReady: reason = "modelNotReady"
            @unknown default: reason = "other"
            }
        }
        return ["available": available, "reason": reason, "contextSize": model.contextSize]
        #else
        return ["available": false, "reason": "moduleMissing"]
        #endif
    }
    @objc(respondTo:history:instructions:language:stream:update:)
    public static func respond(_ q: String, history: [NSDictionary], instructions: String, language: String,
                               stream: Bool, update: @escaping (String, Bool, String?) -> Void) -> AppleLLMTask {
        if !Thread.isMainThread { return DispatchQueue.main.sync { respond(q, history: history, instructions: instructions, language: language, stream: stream, update: update) } }
        current?.supersede()
        let token = AppleLLMTask(); token.lifecycle = TAIResponseLifecycle(update: update); current = token
        let work = Task { @MainActor in
            defer { if current === token { current = nil } }
            func emit(_ text: String, _ done: Bool, _ code: String? = nil) { if !token.cancelled && !Task.isCancelled { token.lifecycle?.emit(text, done: done, code: code) } }
            let state = availability()
            guard state["available"] as? Bool == true else { emit("", true, state["reason"] as? String ?? "other"); return }
            #if canImport(FoundationModels)
            let model = SystemLanguageModel.default
            let ctx = model.contextSize, reserve = taiResponseReserve(contextSize: model.contextSize)
            func count(_ text: String) async -> Int {
                if #available(iOS 26.4, *), let value = try? await model.tokenCount(for: text) { return value }
                return taiEstimateTokens(text)
            }
            let pairs = taiHistoryPairs(history.compactMap { $0 as? [String: String] })
            // Reject malformed rows rather than silently changing role order.
            let validPairs = history.allSatisfy { $0 is [String: String] } ? pairs : []
            var counts: [String: Int] = [:]
            for pair in validPairs { counts[pair.q] = await count(pair.q); counts[pair.a] = await count(pair.a) }
            let instructionCount = await count(instructions), questionCount = await count(q)
            let budget = taiHistoryBudget(contextSize: ctx, instructionsTokens: instructionCount, promptTokens: questionCount, reserve: reserve)
            let trimmed = taiTrimHistory(validPairs, budget: budget, count: { counts[$0] ?? taiEstimateTokens($0) })
            var prefix = TAIPrefixStream()
            for attempt in 0...1 {
                do {
                    try Task.checkCancellation()
                    var entries: [Transcript.Entry] = [.instructions(Transcript.Instructions(segments: [.text(.init(content: instructions))], toolDefinitions: []))]
                    for pair in attempt == 0 ? trimmed : [] {
                        entries.append(.prompt(Transcript.Prompt(segments: [.text(.init(content: pair.q))])))
                        entries.append(.response(Transcript.Response(assetIDs: [], segments: [.text(.init(content: pair.a))])))
                    }
                    let session = LanguageModelSession(model: model, tools: [], transcript: Transcript(entries: entries))
                    let options = GenerationOptions(maximumResponseTokens: reserve)
                    var last = ""
                    if stream {
                        for try await snapshot in session.streamResponse(to: q, options: options) {
                            try Task.checkCancellation(); if token.cancelled { return }
                            last = snapshot.content
                            if let text = prefix.accept(last) { emit(text, false) }
                        }
                    } else { last = try await session.respond(to: q, options: options).content }
                    emit(prefix.finish(last), true); return
                } catch {
                    let code = taiModelError(error)
                    if code == "contextSize" && attempt == 0 && prefix.emitted.isEmpty { continue }
                    emit(prefix.emitted, true, code); return
                }
            }
            #else
            emit("", true, "moduleMissing")
            #endif
        }
        token.install(work); return token
    }
}
#if canImport(FoundationModels)
@available(iOS 26.0, *)
private func taiModelError(_ error: Error) -> String {
    if error is CancellationError { return "cancelled" }
    if #available(iOS 27.0, *) {
        if let value = error as? LanguageModelError {
            switch value {
            case .contextSizeExceeded: return "contextSize"
            case .rateLimited: return "rateLimited"
            case .guardrailViolation: return "guardrail"
            case .refusal: return "refusal"
            case .unsupportedLanguageOrLocale: return "unsupportedLanguage"
            default: return "other"
            }
        }
        if let value = error as? LanguageModelSession.Error, case .concurrentRequests = value { return "concurrentRequests" }
        if let value = error as? SystemLanguageModel.Error, case .assetsUnavailable = value { return "modelNotReady" }
    }
    if let value = error as? LanguageModelSession.GenerationError {
        switch value {
        case .exceededContextWindowSize: return "contextSize"
        case .guardrailViolation: return "guardrail"
        case .rateLimited: return "rateLimited"
        case .refusal: return "refusal"
        case .unsupportedLanguageOrLocale: return "unsupportedLanguage"
        case .concurrentRequests: return "concurrentRequests"
        case .assetsUnavailable: return "modelNotReady"
        default: return "other"
        }
    }
    return "other"
}
#endif
