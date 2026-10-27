import Foundation
import AVFoundation
#if canImport(Speech)
import Speech
#endif

@available(iOS 26.0, *)
@MainActor final class AppleLiveSpeech {
    var onText: ((String, Bool) -> Void)?
    var onFailure: ((String) -> Void)?
    private(set) var lastCode = "other"
    #if canImport(Speech)
    private var analyzer: SpeechAnalyzer?
    private var continuation: AsyncStream<AnalyzerInput>.Continuation?
    private var results: Task<Void, Never>?
    #endif
    private var generation = 0
    func prepare(locale: Locale) async throws -> AVAudioFormat {
        stop(); let epoch = generation
        #if canImport(Speech)
        let authorized = await withCheckedContinuation { continuation in SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0 == .authorized) } }
        guard authorized else { lastCode = "notAuthorized"; throw CaptionFailure.unavailable }
        guard generation == epoch, !Task.isCancelled else { throw CancellationError() }
        guard SpeechTranscriber.isAvailable, let supported = await SpeechTranscriber.supportedLocale(equivalentTo: locale) else { lastCode = "localeUnsupported"; throw CaptionFailure.unavailable }
        guard await SpeechTranscriber.installedLocales.contains(supported) else { lastCode = "assetsMissing"; throw CaptionFailure.unavailable }
        let transcriber = SpeechTranscriber(locale: supported, transcriptionOptions: [], reportingOptions: [.volatileResults, .fastResults], attributeOptions: [])
        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else { throw CaptionFailure.unavailable }
        guard generation == epoch, !Task.isCancelled else { throw CancellationError() }
        let analyzer = SpeechAnalyzer(modules: [transcriber]); self.analyzer = analyzer
        do {
        try await analyzer.prepareToAnalyze(in: format)
        guard generation == epoch, !Task.isCancelled else { throw CancellationError() }
        let pair = AsyncStream<AnalyzerInput>.makeStream(bufferingPolicy: .bufferingOldest(64)); continuation = pair.continuation
        results = Task { [weak self] in
            do {
                for try await result in transcriber.results {
                    guard let self, self.generation == epoch, !Task.isCancelled else { return }
                    self.onText?(String(result.text.characters), result.isFinal)
                }
            } catch { guard let self, self.generation == epoch, !Task.isCancelled else { return }; self.onFailure?("other") }
        }
        try await analyzer.start(inputSequence: pair.stream)
        guard generation == epoch, !Task.isCancelled else { throw CancellationError() }
        return format
        } catch {
            await analyzer.cancelAndFinishNow()
            if generation == epoch { stop() }
            throw error
        }
        #else
        lastCode = "moduleMissing"; throw CaptionFailure.unavailable
        #endif
    }
    func offer(_ buffer: AVAudioPCMBuffer) {
        #if canImport(Speech)
        if let result = continuation?.yield(AnalyzerInput(buffer: buffer)), case .dropped = result { stop(); onFailure?("asr_audio_backpressure") }
        #endif
    }
    func stop() {
        generation += 1
        #if canImport(Speech)
        continuation?.finish(); continuation = nil; results?.cancel(); results = nil
        if let analyzer { Task { await analyzer.cancelAndFinishNow() } }; analyzer = nil
        #endif
    }
}
