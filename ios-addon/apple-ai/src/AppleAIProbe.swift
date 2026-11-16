import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif
#if canImport(Speech)
import Speech
#endif
#if canImport(Translation)
import Translation
#endif

@available(iOS 26.0, *)
@objc(TIOAppleAIProbe) public final class AppleAIProbe: NSObject {
    @objc(moduleVersion) public static var moduleVersion: String { "APPLE-AI-01" }
    @objc(setUILanguage:) public static func setUILanguage(_ code: String) { TAIL10n.language = code }
    @objc(runWithCompletion:) public static func run(_ completion: @escaping (NSDictionary) -> Void) {
        Task { @MainActor in
            var facts: [String: Any] = ["os": ProcessInfo.processInfo.operatingSystemVersionString, "module": moduleVersion,
                "fm.available": false, "fm.reason": "moduleMissing", "speech.available": false,
                "speech.en": "", "speech.zh": "", "speech.enInstalled": false, "speech.zhInstalled": false,
                "translate.enzh": "unsupported", "translate.zhen": "unsupported"]
            #if canImport(FoundationModels)
            let model = SystemLanguageModel.default
            switch model.availability {
            case .available: facts["fm.available"] = true; facts["fm.reason"] = "available"
            case .unavailable(let reason):
                switch reason {
                case .deviceNotEligible: facts["fm.reason"] = "deviceNotEligible"
                case .appleIntelligenceNotEnabled: facts["fm.reason"] = "appleIntelligenceNotEnabled"
                case .modelNotReady: facts["fm.reason"] = "modelNotReady"
                @unknown default: facts["fm.reason"] = "other"
                }
            }
            facts["fm.contextSize"] = model.contextSize
            facts["fm.en"] = model.supportsLocale(Locale(identifier: "en_US"))
            facts["fm.zh"] = model.supportsLocale(Locale(identifier: "zh_CN"))
            facts["fm.languages"] = model.supportedLanguages.count
            #endif
            #if canImport(Speech)
            facts["speech.available"] = SpeechTranscriber.isAvailable
            let english = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: "en_US"))
            let chinese = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: "zh_CN"))
            let installed = await SpeechTranscriber.installedLocales
            facts["speech.en"] = english?.identifier ?? ""
            facts["speech.zh"] = chinese?.identifier ?? ""
            facts["speech.enInstalled"] = english.map { installed.contains($0) } ?? false
            facts["speech.zhInstalled"] = chinese.map { installed.contains($0) } ?? false
            #endif
            #if canImport(Translation)
            let languages = LanguageAvailability()
            func code(_ value: LanguageAvailability.Status) -> String {
                switch value { case .installed: return "installed"; case .supported: return "supported"; case .unsupported: return "unsupported"; @unknown default: return "unsupported" }
            }
            facts["translate.enzh"] = code(await languages.status(from: Locale.Language(identifier: "en"), to: Locale.Language(identifier: "zh-Hans")))
            facts["translate.zhen"] = code(await languages.status(from: Locale.Language(identifier: "zh-Hans"), to: Locale.Language(identifier: "en")))
            #endif
            completion(facts as NSDictionary)
        }
    }
}
