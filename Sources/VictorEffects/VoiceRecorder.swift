import AppKit
import AVFoundation
import Foundation

/// 🎙️ Record voice — the room's voices, from the default input, into an .m4a
/// (2026-11-12). Started from the 𝓯𝔁 menu; while it runs, a **second status
/// item** stands next to 𝓯𝔁: a red ⏹ and the elapsed time. One click on it
/// stops, finalises the file and shows it in Finder.
///
/// Why a status item of its own and not the 🛑 face of 𝓯𝔁: 🛑 is an emergency
/// stop for what the *room sees*, and a panicked click on a demo gone wrong
/// must not also end a recording nobody asked to end. Two lamps, two buttons.
/// And not an overlay: the built-in screen may be mirrored to the room, and a
/// ⏹ floating over the slides would announce the recording to everyone in it.
///
/// No self-termination timer, deliberately: a recording is a thing Victor
/// stops, not an effect. What protects it is that the lamp never goes out
/// while it runs, and that `stop()` runs on teardown so a quit still leaves a
/// playable file (an AAC file is only readable once its header is written).
final class VoiceRecorder: NSObject, AVAudioRecorderDelegate {
    static let shared = VoiceRecorder()

    private var recorder: AVAudioRecorder?
    private var stopItem: NSStatusItem?
    private var tick: Timer?

    var isRecording: Bool { recorder?.isRecording == true }

    /// Called whenever recording starts or stops, so the menu row can retitle.
    var onChange: (() -> Void)?

    func toggle() { isRecording ? stop() : start() }

    func start() {
        guard !isRecording else { return }
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            begin()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                DispatchQueue.main.async { granted ? self.begin() : self.explainDenied() }
            }
        default:
            explainDenied()
        }
    }

    func stop() {
        guard let recorder else { return }
        let url = recorder.url
        let seconds = recorder.currentTime
        recorder.stop()
        self.recorder = nil
        tick?.invalidate(); tick = nil
        if let stopItem { NSStatusBar.system.removeStatusItem(stopItem) }
        stopItem = nil
        effectsInfo("🎙️ Recording stopped after \(Self.clock(seconds)): \(url.path)")
        NSWorkspace.shared.activateFileViewerSelecting([url])
        onChange?()
    }

    // MARK: private

    private func begin() {
        let dir = EffectsConfig.shared.recordingsDir
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let url = dir.appendingPathComponent(Self.fileName(for: Date()))
            let settings: [String: Any] = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 44_100,
                AVNumberOfChannelsKey: 1,
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
            ]
            let r = try AVAudioRecorder(url: url, settings: settings)
            r.delegate = self
            guard r.record() else {
                effectsError("🎙️ AVAudioRecorder refused to start (no input device?)")
                return
            }
            recorder = r
            effectsInfo("🎙️ Recording to \(url.path)")
            showStopItem()
            onChange?()
        } catch {
            effectsError("🎙️ Could not start recording: \(error.localizedDescription)")
        }
    }

    private func showStopItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
                .applying(.init(paletteColors: [.white, .systemRed]))
            button.image = NSImage(systemSymbolName: "stop.circle.fill",
                                   accessibilityDescription: "Stop recording")?
                .withSymbolConfiguration(config)
            button.imagePosition = .imageLeading
            button.toolTip = "Recording voice — click to stop and show the file"
            button.target = self
            button.action = #selector(stopClicked)
        }
        stopItem = item
        refreshClock()
        tick = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.refreshClock()
        }
    }

    private func refreshClock() {
        stopItem?.button?.title = " " + Self.clock(recorder?.currentTime ?? 0)
    }

    @objc private func stopClicked() { stop() }

    private func explainDenied() {
        effectsError("🎙️ Microphone access denied — System Settings › Privacy & Security › Microphone")
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
            NSWorkspace.shared.open(url)
        }
    }

    /// The input vanished (a USB mic unplugged, a Bluetooth headset gone):
    /// AVAudioRecorder stops by itself and says so here, and the lamp has to
    /// go out with it, or it would count up over a recording that has ended.
    func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        guard recorder === self.recorder else { return }
        if !flag { effectsError("🎙️ Recording ended on its own (input lost?)") }
        DispatchQueue.main.async { self.stop() }
    }

    // MARK: pure helpers (tested)

    static func clock(_ seconds: TimeInterval) -> String {
        let s = max(0, Int(seconds))
        return s >= 3600
            ? String(format: "%d:%02d:%02d", s / 3600, (s / 60) % 60, s % 60)
            : String(format: "%d:%02d", s / 60, s % 60)
    }

    static func fileName(for date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH.mm.ss"
        return "Voice \(f.string(from: date)).m4a"
    }
}
