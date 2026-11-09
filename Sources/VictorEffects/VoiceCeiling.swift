import AVFoundation
import CoreAudio
import Foundation

/// 🎚️ **No effect louder than Victor's voice while he screen-shares.**
///
/// In a Zoom or Teams share with the computer's sound shared, the room hears the
/// soundboard through the meeting next to his mic — and on 2026-11-09 the
/// effects came out far louder than his voice. Victor Addons measures the voice
/// on the mic the meeting actually uses (its `VoiceMeter`) and pushes the
/// reference here once a second while a share is up (`GET /voice/ref?sharing=1&ref=<LUFS>`)
/// and once when it ends (`sharing=0`). Every sound that starts meanwhile is held
/// so that
///
///     clip loudness = M(file) + 20·log10(player volume) + system dB ≤ voiceRef + offset
///
/// - `M(file)` — the file's loudest 3 s, EBU R128 short-term LUFS (`Loudness`),
///   of the file **actually played**: its ＋ render when it has one
///   (`DiskBoosts`), measured with every other file by `RecommendedVolumes`.
/// - player volume — everything this app multiplies in already: the tablet's
///   blue wedge × the tile's own bar × the mastering trim. So `M + 20·log10(v)`
///   is "the clip's loudness + the tile gain + the global volume, in dB".
/// - system dB — the macOS output volume, **only when the default output is
///   `ZoomAudioDevice`**: Zoom's *Share sound* makes that virtual device the
///   default output and reads its loopback, and measured 2026-11-09 that device
///   applies its own volume control to what it loops (scalar 0.25 → −12.0 dB on
///   the captured signal). For any other output — Teams' own device included,
///   which did not loop at all with Teams closed — nothing is credited: not
///   knowing means capping harder, never softer.
/// - offset — `voiceCeilingOffsetDb` in `config.json`, default −3.
///
/// **It only ever lowers**: the result is `min(asked, allowed)`. A reference
/// older than 60 s is dropped (a crashed addons must not leave the soundboard
/// muffled for the rest of the day). Every capped play is logged with the dB
/// taken off. Videos are played by addons, which asks `GET /voice/ceiling?key=video:<id>`
/// for the same answer.
enum VoiceCeiling {
    static let staleAfter: TimeInterval = 60
    /// A file not measured yet (the first seconds after launch): assumed this
    /// loud — about the loudest stretch of a −14 LUFS-integrated soundboard clip.
    static let unmeasuredLufs = -10.0
    static let shareCaptureDevice = "ZoomAudioDevice"

    // MARK: - The formula (pure; VoiceCeilingTests)

    /// The highest player volume (0…1) at which a file at `clipLufs` stays
    /// at or under `voiceRef + offset`.
    static func maxVolume(clipLufs: Double, voiceRef: Double, offset: Double, systemDb: Double = 0) -> Float {
        let db = voiceRef + offset - clipLufs - systemDb
        return Float(min(1, pow(10, db / 20)))
    }

    /// `asked`, or less — never more.
    static func capped(_ asked: Float, clipLufs: Double, voiceRef: Double, offset: Double,
                       systemDb: Double = 0) -> (volume: Float, takenDb: Double) {
        let allowed = maxVolume(clipLufs: clipLufs, voiceRef: voiceRef, offset: offset, systemDb: systemDb)
        guard asked > allowed else { return (asked, 0) }
        return (allowed, 20 * log10(Double(asked) / Double(max(allowed, 1e-6))))
    }

    // MARK: - State (main thread)

    private(set) static var sharing = false
    private(set) static var voiceRef: Double?
    private(set) static var refSource = ""
    private(set) static var receivedAt: Date?
    /// Every audio file measured (path, symlinks resolved) → its loudest 3 s;
    /// nil = silent. Filled by `RecommendedVolumes`' background pass.
    static var fileLoudness: [String: Double?] = [:]

    static var active: Bool {
        guard sharing, voiceRef != nil, let at = receivedAt else { return false }
        return Date().timeIntervalSince(at) <= staleAfter
    }

    static func key(_ url: URL) -> String { url.resolvingSymlinksInPath().standardizedFileURL.path }

    /// `GET /voice/ref?sharing=0|1&ref=<LUFS>&src=…` from addons.
    static func receive(sharing on: Bool, ref: Double?, source: String) {
        let edge = on != sharing
        sharing = on
        receivedAt = Date()
        if on, let ref { voiceRef = ref; refSource = source }
        if !on { voiceRef = nil; refSource = "" }
        if edge {
            effectsInfo("🎚️ screen share \(on ? "ON — effects held under the voice" : "OFF — effects back to their own level")"
                + (on ? String(format: " (voice %.1f LUFS %@, offset %+.1f dB)", voiceRef ?? .nan, refSource,
                                EffectsConfig.shared.voiceCeilingOffsetDb) : ""))
            CeilingPlayer.reapplyAll()
        }
    }

    /// The macOS output volume in dB, counted only when Zoom's share device is
    /// the default output (see the type's note); 0 otherwise.
    static func systemDb() -> Double {
        var a = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                           mScope: kAudioObjectPropertyScopeGlobal,
                                           mElement: kAudioObjectPropertyElementMain)
        var dev = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &a, 0, nil, &size, &dev) == noErr
        else { return 0 }
        var nameAddr = AudioObjectPropertyAddress(mSelector: kAudioObjectPropertyName,
                                                  mScope: kAudioObjectPropertyScopeGlobal,
                                                  mElement: kAudioObjectPropertyElementMain)
        var name: Unmanaged<CFString>?
        size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(dev, &nameAddr, 0, nil, &size, &name) == noErr,
              (name?.takeRetainedValue() as String?) == shareCaptureDevice else { return 0 }
        var volAddr = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyVolumeDecibels,
                                                 mScope: kAudioObjectPropertyScopeOutput,
                                                 mElement: kAudioObjectPropertyElementMain)
        var db: Float32 = 0
        size = UInt32(MemoryLayout<Float32>.size)
        guard AudioObjectGetPropertyData(dev, &volAddr, 0, nil, &size, &db) == noErr, db.isFinite else { return 0 }
        return Double(min(0, db))
    }

    /// The loudness of the clip `url` as measured (render included), and whether it was.
    static func loudness(of url: URL) -> (lufs: Double?, measured: Bool) {
        if let v = fileLoudness[key(url)] { return (v, true) }
        return (unmeasuredLufs, false)
    }

    /// The one call every player goes through (`CeilingPlayer`). `log` is false
    /// for the steps of a fade and for re-reads.
    static func clamp(_ asked: Float, url: URL?, log: Bool) -> Float {
        guard active, let ref = voiceRef, let url, asked > 0 else { return asked }
        let (lufs, measured) = loudness(of: url)
        guard let lufs else { return asked }                    // a silent file is never too loud
        let sys = systemDb()
        let offset = EffectsConfig.shared.voiceCeilingOffsetDb
        let r = capped(asked, clipLufs: lufs, voiceRef: ref, offset: offset, systemDb: sys)
        if log {
            let what = String(format: "%@ vol %.2f → %.2f%@ (clip %.1f LUFS%@ at %+.1f dB, sys %+.1f dB; voice %.1f %@ %+.1f → ≤ %.1f)",
                              url.lastPathComponent, asked, r.volume,
                              r.takenDb > 0 ? String(format: ", −%.1f dB", r.takenDb) : ", under the voice",
                              lufs, measured ? "" : " unmeasured", 20 * log10(Double(asked)), sys,
                              ref, refSource, offset, ref + offset)
            effectsInfo("🎚️ \(r.takenDb > 0 ? "capped" : "kept") \(what)")
        }
        return r.volume
    }

    /// `GET /voice/ceiling?key=video:<id>|file=<name>&volume=<0…1>` — the same
    /// answer for a clip this app does not play itself (addons' videos), and the
    /// test hook that shows the computation with the share on or off.
    static func ceilingJSON(key: String?, file: String?, volume: Float) -> String {
        var lufs: Double?
        var measured = false
        var subject = key ?? file ?? ""
        if let key {
            let t = RecommendedVolumes.liveTable
            lufs = t.current[key] ?? t.maxima[key]
            measured = lufs != nil
        } else if let file, let url = SoundManager.shared.soundURL(for: file) {
            (lufs, measured) = loudness(of: url)
            subject = url.lastPathComponent
        }
        let offset = EffectsConfig.shared.voiceCeilingOffsetDb
        let sys = systemDb()
        var out = volume
        var taken = 0.0
        var maxV: Float?
        if active, let ref = voiceRef, let lufs {
            maxV = maxVolume(clipLufs: lufs, voiceRef: ref, offset: offset, systemDb: sys)
            (out, taken) = capped(volume, clipLufs: lufs, voiceRef: ref, offset: offset, systemDb: sys)
        }
        func n(_ v: Double?) -> String { v.map { String(format: "%.2f", $0) } ?? "null" }
        return "{\"subject\":\(jsonString(subject)),\"sharing\":\(sharing),\"active\":\(active)"
            + ",\"voiceRef\":\(n(voiceRef)),\"voiceRefSource\":\(jsonString(refSource)),\"offsetDb\":\(offset)"
            + ",\"systemDb\":\(n(sys)),\"clipLufs\":\(n(lufs)),\"measured\":\(measured)"
            + ",\"asked\":\(String(format: "%.3f", volume)),\"volume\":\(String(format: "%.3f", out))"
            + ",\"maxVolume\":\(maxV.map { String(format: "%.3f", $0) } ?? "null"),\"takenDb\":\(String(format: "%.2f", taken))"
            + ",\"refAgeS\":\(receivedAt.map { String(format: "%.1f", Date().timeIntervalSince($0)) } ?? "null")}"
    }

    private static func jsonString(_ s: String) -> String {
        let data = (try? JSONSerialization.data(withJSONObject: [s])) ?? Data()
        return String((String(data: data, encoding: .utf8) ?? "[\"\"]").dropFirst().dropLast())
    }
}

/// Every soundboard player (`SoundManager.player(contentsOf:)` builds only
/// these): the volume it is asked for goes through `VoiceCeiling.clamp`, on
/// every path — the press, a live drag of the wedge or the tile bar, a fade-in —
/// so no call site can forget it. It remembers what it was asked, so a share
/// that starts or ends mid-clip re-applies the cap (`reapplyAll`).
final class CeilingPlayer: AVAudioPlayer {
    private(set) var asked: Float = 1
    private var logged = false
    private static let live = NSHashTable<CeilingPlayer>.weakObjects()

    private var levelled = false

    override var volume: Float {
        get { super.volume }
        set {
            asked = newValue
            levelled = true
            // Logged once per player, on the first level it is given while capping matters.
            let log = !logged && VoiceCeiling.active && newValue > 0
            if log { logged = true }
            super.volume = VoiceCeiling.clamp(newValue, url: url, log: log)
            Self.live.add(self)
        }
    }

    override func setVolume(_ volume: Float, fadeDuration duration: TimeInterval) {
        asked = volume
        levelled = true
        let log = !logged && VoiceCeiling.active && volume > 0
        if log { logged = true }
        super.setVolume(VoiceCeiling.clamp(volume, url: url, log: log), fadeDuration: duration)
        Self.live.add(self)
    }

    /// A player nobody gave a level plays at AVAudioPlayer's default 1.0 —
    /// which is a level too, and goes through the ceiling like any other.
    override func play() -> Bool {
        Self.live.add(self)
        if !levelled { volume = super.volume }
        return super.play()
    }

    override func play(atTime time: TimeInterval) -> Bool {
        Self.live.add(self)
        if !levelled { volume = super.volume }
        return super.play(atTime: time)
    }

    /// `GET /test/voice/players` — every player still sounding: the file, the
    /// volume it was asked for and the one it really plays at.
    static var playingJSON: String {
        let rows = live.allObjects.filter(\.isPlaying).map { p in
            String(format: "{\"file\":\"%@\",\"asked\":%.3f,\"volume\":%.3f}",
                   p.url?.lastPathComponent ?? "?", p.asked, p.volume)
        }
        return "{\"sharing\":\(VoiceCeiling.active),\"players\":[\(rows.joined(separator: ","))]}"
    }

    /// A share edge: every live player is levelled again from what it was asked.
    static func reapplyAll() {
        for p in live.allObjects where p.isPlaying {
            p.logged = false
            p.volume = p.asked
        }
    }
}
