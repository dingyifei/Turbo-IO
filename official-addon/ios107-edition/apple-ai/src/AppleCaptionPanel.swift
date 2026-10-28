import Foundation
import UIKit
import SwiftUI
import AVFoundation
#if canImport(Translation)
import Translation
#endif

@available(iOS 26.0, *)
@objc(TIOAppleCaptionHost) @MainActor public final class AppleCaptionHost: NSObject {
    private static var handler: ((String, NSDictionary) -> NSDictionary)?
    @objc(configure:) nonisolated public static func configure(_ callback: @escaping (String, NSDictionary) -> NSDictionary) {
        if Thread.isMainThread { MainActor.assumeIsolated { handler = callback } }
        else { DispatchQueue.main.sync { MainActor.assumeIsolated { handler = callback } } }
    }
    static func call(_ name: String, _ args: NSDictionary = [:]) -> NSDictionary { handler?(name, args) ?? ["available": false] }
}

@available(iOS 26.0, *)
@objc(TIOAppleCaptionPanel) @MainActor public final class AppleCaptionPanel: UITableViewController {
    @objc nonisolated public static func makeController() -> UIViewController {
        if Thread.isMainThread { return MainActor.assumeIsolated { AppleCaptionPanel(style: .insetGrouped) } }
        return DispatchQueue.main.sync { MainActor.assumeIsolated { AppleCaptionPanel(style: .insetGrouped) } }
    }
    private let prefs = UserDefaults(suiteName: "io.turboio.official-private-addon")!
    private let mic = CaptionMicrophoneInput(), speech = AppleLiveSpeech(), translator = CaptionLocalTranslation()
    private var direction = "en-zh", glasses = false, hostAvailable = false
    private var ports: [CaptionMicrophoneInput.Port] = [], portUID = "", portName = ""
    private var active = false, starting = false, preparing = false, generation = 0
    private var sid = "", state = "", original = "", translated = "", sent = ""
    private var lines: [String] = [], pending: [String] = []
    private var timer: Timer?, startTask: Task<Void, Never>?, translationTask: Task<Void, Never>?
    private var began = Date(), lastSend = Date.distantPast
    private let sourceView = UITextView(), targetView = UITextView()
    private var source: String { direction.hasPrefix("zh") ? "zh-Hans" : "en" }
    private var target: String { direction == "en-zh" ? "zh-Hans" : direction == "zh-en" ? "en" : source }
    private var locale: String { source == "en" ? "en-US" : "zh-CN" }
    private func t(_ en: String, _ zh: String) -> String { TAIL10n.t(en, zh) }
    public override func viewDidLoad() {
        super.viewDidLoad(); title = t("Live captions (on-device)", "实时字幕（本机）")
        if let value = prefs.string(forKey: "appleCaptionDirection"), ["en-zh", "zh-en", "en", "zh"].contains(value) { direction = value }
        hostAvailable = AppleCaptionHost.call("status")["available"] as? Bool == true
        glasses = hostAvailable && prefs.bool(forKey: "appleCaptionGlasses")
        if !hostAvailable { prefs.set(false, forKey: "appleCaptionGlasses") }
        for view in [sourceView, targetView] { view.isEditable = false; view.font = .preferredFont(forTextStyle: .body) }
        mic.onBuffer = { [weak self] buffer in self?.speech.offer(buffer) }
        mic.onFailure = { [weak self] _ in guard let self else { return }; self.stop(self.t("Microphone route changed; capture stopped.", "麦克风路由改变，已停止收音。")) }
        speech.onText = { [weak self] text, final in self?.receive(text, final: final) }
        speech.onFailure = { [weak self] _ in guard let self else { return }; self.stop(self.t("Speech capture stopped. Check resources and the microphone route.", "语音收集已停止，请检查资源和麦克风路由。")) }
        NotificationCenter.default.addObserver(self, selector: #selector(inactive), name: UIApplication.willResignActiveNotification, object: nil)
    }
    deinit { NotificationCenter.default.removeObserver(self) }
    public override func viewWillDisappear(_ animated: Bool) { super.viewWillDisappear(animated); stop(t("Stopped", "已停止")) }
    @objc private func inactive() { stop(t("App is no longer active; capture stopped.", "应用已离开前台，收音已停止。")) }
    public override func numberOfSections(in tableView: UITableView) -> Int { 5 }
    public override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { section == 0 ? 3 : section == 4 ? 2 : 1 }
    public override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        [t("Settings", "设置"), t("Session", "会话"), t("Source text", "原文"), t("Translation", "译文"), t("Resources", "资源")][section]
    }
    public override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        section == 1 ? state : section == 4 ? t("Prepare the source speech and translation packs before starting. Audio is not saved. Sessions stop after 20 minutes.", "请先准备源语言的语音及翻译资源。不保存音频，会话在 20 分钟后停止。") : nil
    }
    public override func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat { [2,3].contains(indexPath.section) ? 150 : UITableView.automaticDimension }
    public override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil); cell.textLabel?.numberOfLines = 0; cell.detailTextLabel?.numberOfLines = 0
        switch indexPath.section {
        case 0:
            cell.textLabel?.text = [t("Microphone", "麦克风"), t("Direction", "方向"), t("Glasses sync", "同步眼镜")][indexPath.row]
            if indexPath.row == 0 { cell.detailTextLabel?.text = portName.isEmpty ? t("Choose input", "选择输入") : portName }
            if indexPath.row == 1 { cell.detailTextLabel?.text = direction }
            if indexPath.row == 2 { cell.detailTextLabel?.text = hostAvailable ? (glasses ? t("On", "开") : t("Off", "关")) : t("Glasses host unavailable; phone only", "眼镜宿主不可用，仅手机显示"); cell.isUserInteractionEnabled = hostAvailable }
        case 1: cell.textLabel?.text = active || starting ? t("Stop", "停止") : t("Start", "开始")
        case 2,3:
            let view = indexPath.section == 2 ? sourceView : targetView; view.translatesAutoresizingMaskIntoConstraints = false; cell.contentView.addSubview(view)
            NSLayoutConstraint.activate([view.leadingAnchor.constraint(equalTo: cell.contentView.leadingAnchor, constant: 12),view.trailingAnchor.constraint(equalTo: cell.contentView.trailingAnchor, constant: -12),view.topAnchor.constraint(equalTo: cell.contentView.topAnchor),view.bottomAnchor.constraint(equalTo: cell.contentView.bottomAnchor)])
        default: cell.textLabel?.text = indexPath.row == 0 ? t("Prepare speech pack", "准备语音资源") : t("Prepare translation pack", "准备翻译资源")
        }
        return cell
    }
    private func choose(_ title: String, values: [String], action: @escaping (Int) -> Void) {
        let sheet = UIAlertController(title: title, message: nil, preferredStyle: .actionSheet)
        for (index, value) in values.enumerated() { sheet.addAction(UIAlertAction(title: value, style: .default) { _ in action(index) }) }
        sheet.addAction(UIAlertAction(title: t("Cancel", "取消"), style: .cancel))
        sheet.popoverPresentationController?.sourceView = view; sheet.popoverPresentationController?.sourceRect = CGRect(x: view.bounds.midX, y: 100, width: 1, height: 1); present(sheet, animated: true)
    }
    public override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        if indexPath.section == 1 { if active || starting { stop(t("Stopped", "已停止")) } else { confirm() }; return }
        guard !active, !starting, !preparing else { return }
        if indexPath.section == 0 {
            switch indexPath.row {
            case 0:
                confirmMicrophoneSelection()
            case 1: choose(t("Direction", "方向"), values: [t("English → Chinese", "英语 → 中文"),t("Chinese → English", "中文 → 英语"),t("English only", "仅英语"),t("Chinese only", "仅中文")]) { [weak self] index in guard let self else { return }; self.direction = ["en-zh","zh-en","en","zh"][index]; self.prefs.set(self.direction, forKey: "appleCaptionDirection"); self.tableView.reloadData() }
            default: if hostAvailable { glasses.toggle(); prefs.set(glasses, forKey: "appleCaptionGlasses"); tableView.reloadData() }
            }
        } else if indexPath.section == 4 {
            if indexPath.row == 0 { preparing = true; AppleSpeech.prepare(locale, progress: { [weak self] fraction in guard let self else { return }; self.state = self.t("Preparing speech", "正在准备语音") + String(format: " %.0f%%", fraction * 100); self.tableView.reloadData() }, completion: { [weak self] code in guard let self else { return }; self.preparing = false; self.state = code == nil ? self.t("Speech pack ready", "语音资源已就绪") : self.t("Speech pack unavailable; check system download authorization.", "语音资源不可用，请检查系统下载授权。"); self.tableView.reloadData() }) }
            else {
                #if canImport(Translation)
                navigationController?.pushViewController(UIHostingController(rootView: AppleTranslationPreparation(source: source, target: target)), animated: true)
                #endif
            }
        }
    }
    private func confirmMicrophoneSelection() {
        let epoch = generation
        let alert = UIAlertController(title: t("Inspect microphone inputs?", "查看麦克风输入？"), message: t("Confirm no recording, voice chat, playback or navigation is active. Input discovery temporarily configures the audio session.", "请确认录音、语音对话、播放和导航均未运行。查找输入会临时配置音频会话。"), preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: t("Cancel", "取消"), style: .cancel))
        alert.addAction(UIAlertAction(title: t("Confirm idle and inspect", "确认空闲并查看"), style: .default) { [weak self, weak alert] _ in
            let inspect: () -> Void = { [weak self] in self?.inspectMicrophones(epoch: epoch) }
            if let alert, alert.presentingViewController != nil { alert.dismiss(animated: true, completion: inspect) } else { inspect() }
        })
        present(alert, animated: true)
    }
    private func inspectMicrophones(epoch: Int) {
        guard generation == epoch, !active, !starting, !preparing, viewIfLoaded?.window != nil, UIApplication.shared.applicationState == .active else { return }
        // Template availability controls glasses output, not live conflict checks.
        guard AppleCaptionHost.call("inspect")["ok"] as? Bool == true else {
            state = t("Glasses are busy. End their session before inspecting microphone inputs.", "眼镜正忙，请先结束会话再查看麦克风输入。")
            tableView.reloadData(); return
        }
        preparing = true
        Task { [weak self] in guard let self else { return }; defer { self.preparing = false; self.mic.stop() }
            do {
                self.ports = try await self.mic.prepare(); try Task.checkCancellation()
                guard self.generation == epoch, self.viewIfLoaded?.window != nil, UIApplication.shared.applicationState == .active else { throw CancellationError() }
                self.choose(self.t("Microphone", "麦克风"), values: self.ports.map(\.name)) { [weak self] index in
                    guard let self, self.generation == epoch, self.ports.indices.contains(index) else { return }
                    self.portUID = self.ports[index].uid; self.portName = self.ports[index].name; self.tableView.reloadData()
                }
            } catch { if self.generation == epoch { self.state = self.t("Microphone permission or route unavailable.", "麦克风权限或路由不可用。"); self.tableView.reloadData() } }
        }
    }
    private func confirm() {
        let alert = UIAlertController(title: t("Start microphone?", "开始收音？"), message: t("Confirm no recording, voice chat or navigation is active and the glasses are at Home. Recognition and translation run on this phone.", "请确认录音、语音对话和导航均未运行，眼镜已回到首页。识别和翻译在此手机执行。"), preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: t("Cancel", "取消"), style: .cancel)); alert.addAction(UIAlertAction(title: t("Confirm idle and start", "确认空闲并开始"), style: .default) { [weak self] _ in self?.start() }); present(alert, animated: true)
    }
    private func start() {
        guard !active, !starting, !preparing else { return }; starting = true; generation += 1; let epoch = generation
        state = t("Starting on-device speech…", "正在启动本机语音…"); tableView.reloadData()
        startTask = Task { [weak self] in guard let self else { return }
            do {
                if self.glasses {
                    guard let value = AppleCaptionHost.call("start")["sid"] as? String, !value.isEmpty else { throw CaptionFailure.unavailable }; self.sid = value
                    var ready = false
                    for _ in 0..<40 { try await Task.sleep(nanoseconds: 250_000_000); try Task.checkCancellation(); let status = AppleCaptionHost.call("status"); guard status["sid"] as? String == value else { throw CaptionFailure.unavailable }; if status["phase"] as? String == "ready" { ready = true; break }; if ["stopping","uncertain","idle"].contains(status["phase"] as? String ?? "") { break } }
                    guard ready else { throw CaptionFailure.unavailable }
                }
                let format = try await self.speech.prepare(locale: Locale(identifier: self.locale))
                self.ports = try await self.mic.prepare()
                let chosen = self.portUID.isEmpty ? self.ports.first(where: { $0.type == AVAudioSession.Port.builtInMic.rawValue }) : self.ports.first(where: { $0.uid == self.portUID })
                guard let chosen, self.generation == epoch, UIApplication.shared.applicationState == .active else { throw CaptionFailure.routeChanged }
                self.portUID = chosen.uid; self.portName = chosen.name
                try await self.mic.start(uid: chosen.uid, format: format); try Task.checkCancellation()
                guard self.generation == epoch else { throw CancellationError() }
                self.starting = false; self.active = true; self.began = Date(); self.original = ""; self.translated = ""; self.sent = ""; self.lines = []; self.pending = []; self.lastSend = .distantPast
                self.state = self.t("Listening on device", "正在本机收音"); self.tableView.reloadData()
                self.timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in Task { @MainActor [weak self] in self?.pump() } }
            } catch { if self.generation == epoch { self.stop(self.t("Cannot start. Prepare speech assets and check microphone permission, input route and glasses connection.", "无法启动，请准备语音资源并检查麦克风权限、输入路由和眼镜连接。")) } }
        }
    }
    private func receive(_ text: String, final: Bool) {
        guard active || starting else { return }; original = text; sourceView.text = text
        guard final, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        if source == target { translated = ""; targetView.text = ""; return }
        guard pending.count < 4 else { stop(t("Translation queue full; capture stopped.", "翻译队列已满，收音已停止。")); return }
        pending.append(text); translateNext()
    }
    private func translateNext() {
        guard active, translationTask == nil, !pending.isEmpty else { return }
        let text = pending.removeFirst(), epoch = generation
        translationTask = Task { [weak self] in guard let self else { return }
            do { let result = try await self.translator.translate(text, source: self.source, target: self.target); guard self.generation == epoch, !Task.isCancelled else { return }; self.lines.append(result); self.lines = Array(self.lines.suffix(2)); self.translated = self.lines.joined(separator: "\n"); self.targetView.text = self.translated }
            catch { if self.generation == epoch { self.state = self.t("Prepare the translation pack; speech recognition continues.", "请准备翻译资源，语音识别继续运行。"); self.tableView.reloadData() } }
            if self.generation == epoch { self.translationTask = nil; self.translateNext() }
        }
    }
    private func pump() {
        guard active else { return }; translateNext()
        if Date().timeIntervalSince(began) >= 1200 { stop(t("20-minute session limit reached.", "已达到 20 分钟会话上限。")); return }
        guard !sid.isEmpty else { return }; let status = AppleCaptionHost.call("status")
        guard status["sid"] as? String == sid, status["phase"] as? String == "ready" else { stop(t("Glasses session ended; capture stopped.", "眼镜会话结束，收音已停止。")); return }
        let text = taiCaptionDisplay(source: original, translated: translated, sourceLabel: source == "en" ? "EN" : "中", targetLabel: target == "en" ? "EN" : "中", preview: false)
        guard !text.isEmpty, text != sent, Date().timeIntervalSince(lastSend) >= 0.5, status["pending"] as? Bool != true else { return }
        if AppleCaptionHost.call("text", ["sid": sid, "text": text])["ok"] as? Bool == true { sent = text; lastSend = Date() }
    }
    private func stop(_ reason: String) {
        generation += 1; starting = false; active = false; startTask?.cancel(); startTask = nil; timer?.invalidate(); timer = nil
        mic.stop(); speech.stop(); translator.cancel(); translationTask?.cancel(); translationTask = nil; pending = []
        if !sid.isEmpty { _ = AppleCaptionHost.call("stop", ["sid": sid]); sid = "" }
        state = reason; if isViewLoaded { tableView.reloadData() }
    }
}
#if canImport(Translation)
@available(iOS 26.0, *)
private struct AppleTranslationPreparation: View {
    let source: String, target: String
    @State private var configuration: TranslationSession.Configuration?
    @State private var status = TAIL10n.t("Download the matching system language packs before translating.", "翻译前请下载对应的系统语言资源。")
    var body: some View {
        VStack(spacing: 24) {
            Text(TAIL10n.t("Translation packs", "翻译资源")).font(.title2)
            Text(source + " → " + target); Text(status)
            Button(TAIL10n.t("Check and prepare packs", "检查并准备资源")) { configuration = .init(source: Locale.Language(identifier: source), target: Locale.Language(identifier: target)); configuration?.invalidate() }
        }.padding().translationTask(configuration) { session in
            do { try await session.prepareTranslation(); await MainActor.run { status = TAIL10n.t("Translation packs ready.", "翻译资源已就绪。") } }
            catch { await MainActor.run { status = TAIL10n.t("Pack not ready. Check system download authorization and language support.", "资源尚未就绪，请检查系统下载授权和语言支持。") } }
        }
    }
}
#endif
