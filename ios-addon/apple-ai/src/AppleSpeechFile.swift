import Foundation
import AVFoundation
#if canImport(Speech)
import Speech
#endif

@available(iOS 26.0, *)
@objc(TIOAppleSpeechTask) public final class AppleSpeechTask: NSObject {
    private let lock = NSLock()
    private var stopped = false
    private var work: Task<Void, Never>?
    private var cleanup: (() -> Void)?
    var cancelled: Bool { lock.lock(); defer { lock.unlock() }; return stopped }
    func install(_ task: Task<Void, Never>) { lock.lock(); work = task; let stop = stopped; lock.unlock(); if stop { task.cancel() } }
    func onCancel(_ action: @escaping () -> Void) { lock.lock(); cleanup = action; let stop = stopped; lock.unlock(); if stop { action() } }
    @objc public func cancel() {
        if !Thread.isMainThread { DispatchQueue.main.sync { self.cancel() }; return }
        lock.lock(); stopped = true; let task = work, action = cleanup; work = nil; cleanup = nil; lock.unlock(); task?.cancel(); action?() }
}
@available(iOS 26.0, *)
@objc(TIOAppleSpeech) public final class AppleSpeech: NSObject {
    @objc(statusForLocale:completion:) public static func status(_ code: String, completion: @escaping (NSDictionary) -> Void) {
        Task { @MainActor in completion(await facts(code)) }
    }
    @MainActor private static func facts(_ code: String) async -> NSDictionary {
        #if canImport(Speech)
        guard SpeechTranscriber.isAvailable, let locale = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: code)) else { return ["supported": "", "installed": false, "assets": "unsupported"] }
        let transcriber = SpeechTranscriber(locale: locale, preset: .transcription)
        let state = await AssetInventory.status(forModules: [transcriber])
        let assets: String
        switch state { case .installed: assets = "installed"; case .supported: assets = "supported"; case .downloading: assets = "downloading"; case .unsupported: assets = "unsupported"; @unknown default: assets = "unsupported" }
        return ["supported": locale.identifier, "installed": state == .installed, "assets": assets]
        #else
        return ["supported": "", "installed": false, "assets": "unsupported"]
        #endif
    }
    @objc(prepareLocale:progress:completion:) public static func prepare(_ code: String, progress: @escaping (Double) -> Void, completion: @escaping (String?) -> Void) {
        Task { @MainActor in
            #if canImport(Speech)
            guard let locale = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: code)) else { completion("localeUnsupported"); return }
            do {
                _ = try await AssetInventory.reserve(locale: locale)
                let transcriber = SpeechTranscriber(locale: locale, preset: .transcription)
                if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
                    let poller = Task { @MainActor in
                        while !Task.isCancelled { progress(request.progress.fractionCompleted); try? await Task.sleep(nanoseconds: 500_000_000) }
                    }
                    defer { poller.cancel() }
                    try await request.downloadAndInstall()
                }
                guard (await facts(code))["installed"] as? Bool == true else { completion("assetsMissing"); return }
                progress(1); completion(nil)
            } catch { completion(error is CancellationError ? "cancelled" : "assetsMissing") }
            #else
            completion("moduleMissing")
            #endif
        }
    }
    @objc(transcribeFile:locale:progress:completion:) public static func transcribe(_ url: URL, locale code: String, progress: @escaping (Double) -> Void, completion: @escaping (String?, String?) -> Void) -> AppleSpeechTask {
        let token = AppleSpeechTask()
        let work = Task { @MainActor in
            func finish(_ text: String?, _ code: String?) { if !token.cancelled { completion(text, code) } }
            #if canImport(Speech)
            let authorized = await withCheckedContinuation { continuation in SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0 == .authorized) } }
            guard !token.cancelled else { return }
            guard authorized else { finish(nil, "notAuthorized"); return }
            guard url.isFileURL, let locale = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: code)) else { finish(nil, "localeUnsupported"); return }
            guard (await facts(code))["installed"] as? Bool == true else { finish(nil, "assetsMissing"); return }
            let transcriber = SpeechTranscriber(locale: locale, transcriptionOptions: [], reportingOptions: [], attributeOptions: [.audioTimeRange])
            let analyzer = SpeechAnalyzer(modules: [transcriber])
            token.onCancel { Task { await analyzer.cancelAndFinishNow() } }
            do {
                let file = try AVAudioFile(forReading: url)
                let duration = Double(file.length) / file.processingFormat.sampleRate
                guard duration.isFinite, duration > 0, duration <= 14400 else { finish(nil, "decodeFailed"); return }
                let collector = Task { @MainActor () throws -> [(start: Double, text: String)] in
                    var segments: [(start: Double, text: String)] = []
                    for try await result in transcriber.results where result.isFinal {
                        try Task.checkCancellation(); if token.cancelled { throw CancellationError() }
                        segments.append((result.range.start.seconds, String(result.text.characters)))
                        progress(min(1, max(0, result.range.end.seconds / duration)))
                    }
                    return segments
                }
                do {
                    if let last = try await analyzer.analyzeSequence(from: file) { try await analyzer.finalizeAndFinish(through: last) }
                    else { await analyzer.cancelAndFinishNow() }
                    let segments = try await collector.value
                    finish(taiTranscriptMarkdown(segments), nil)
                } catch { collector.cancel(); await analyzer.cancelAndFinishNow(); throw error }
            } catch { await analyzer.cancelAndFinishNow(); finish(nil, error is CancellationError ? "cancelled" : "other") }
            #else
            finish(nil, "moduleMissing")
            #endif
        }
        token.install(work); return token
    }
}
