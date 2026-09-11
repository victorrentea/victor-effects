import Foundation

/// Everything that is *this Mac's* rather than *the app's*.
///
/// The app is public; the sounds are not. 99 mp3 (many of them copyrighted)
/// live in a private folder, so nothing here hardcodes a path into anyone's
/// home directory — `soundsDir` is read at launch from
/// `~/.victor-effects/config.json` and can be re-read with `GET /config/reload`.
struct EffectsConfigValues: Equatable {
    var port: UInt16 = 55124
    /// Folder with the `NN_name.mp3` soundboard files, `sound-timing.json`,
    /// `tiles.json` and `tiles/`. Shared with the tablet repo on this Mac.
    var soundsDir: String = "~/.victor-effects/sounds"
    /// Optional extra images/gifs that are too large or too licensed to commit
    /// (love hands, brother, gangnam frames, the fail stamp).
    var assetsDir: String = "~/.victor-effects/assets"
    /// Fire-and-forget GET target for cross-app gestures (`?type=coffee-popped`).
    /// Empty = no webhook.
    var eventWebhook: String = ""
    /// Substring of the Bluetooth speaker's name to keep awake. Empty disables
    /// the keep-alive entirely, which is the right default for everyone but the
    /// one Mac that owns the speaker.
    var bluetoothSpeakerNameMatch: String = ""
    /// `"builtin"` (default) | `"main"` | any substring of a screen's
    /// `localizedName`.
    var overlayScreen: String = "builtin"
    /// Emoji that charge up when the cursor hovers them and pop into a webhook.
    var chargeEmoji: [String] = ["☕"]

    /// Pure parser — the tests drive this with literal JSON and a literal
    /// environment, so no test ever depends on what is on this machine.
    static func parse(jsonData: Data?, env: [String: String] = [:]) -> EffectsConfigValues {
        var v = EffectsConfigValues()
        if let data = jsonData,
           let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
            if let p = obj["port"] as? NSNumber, p.intValue > 0, p.intValue < 65536 {
                v.port = UInt16(p.intValue)
            }
            if let s = obj["soundsDir"] as? String, !s.isEmpty { v.soundsDir = s }
            if let s = obj["assetsDir"] as? String, !s.isEmpty { v.assetsDir = s }
            if let s = obj["eventWebhook"] as? String { v.eventWebhook = s }
            if let s = obj["bluetoothSpeakerNameMatch"] as? String { v.bluetoothSpeakerNameMatch = s }
            if let s = obj["overlayScreen"] as? String, !s.isEmpty { v.overlayScreen = s }
            if let a = obj["chargeEmoji"] as? [String], !a.isEmpty { v.chargeEmoji = a }
        }
        // Env wins over the file: it is how you start a second copy on another
        // port without editing the config the running one shares.
        if let p = env["VICTOR_EFFECTS_PORT"], let n = Int(p), n > 0, n < 65536 {
            v.port = UInt16(n)
        }
        if let s = env["VICTOR_EFFECTS_SOUNDS_DIR"], !s.isEmpty { v.soundsDir = s }
        return v
    }
}

final class EffectsConfig {
    static let shared = EffectsConfig()

    private(set) var values = EffectsConfigValues()

    /// Path of the config file actually consulted (`VICTOR_EFFECTS_CONFIG`
    /// overrides it, which is how the tests and a second instance stay out of
    /// each other's way).
    static var configPath: String {
        if let p = ProcessInfo.processInfo.environment["VICTOR_EFFECTS_CONFIG"], !p.isEmpty {
            return expand(p)
        }
        return expand("~/.victor-effects/config.json")
    }

    static var configDir: String { (configPath as NSString).deletingLastPathComponent }

    private init() { reload() }

    @discardableResult
    func reload() -> EffectsConfigValues {
        let path = Self.configPath
        let data = FileManager.default.contents(atPath: path)
        if data == nil {
            effectsInfo("No config at \(path) — using defaults (port 55124, soundsDir ~/.victor-effects/sounds)")
        }
        values = EffectsConfigValues.parse(jsonData: data, env: ProcessInfo.processInfo.environment)
        effectsInfo("Config: port=\(values.port) soundsDir=\(soundsDir.path) assetsDir=\(assetsDir.path) "
            + "webhook=\(values.eventWebhook.isEmpty ? "-" : values.eventWebhook) "
            + "screen=\(values.overlayScreen) bt=\(values.bluetoothSpeakerNameMatch.isEmpty ? "-" : values.bluetoothSpeakerNameMatch)")
        return values
    }

    /// Point the app at different values without a file. Only the tests use it:
    /// half of what lives here is a path, and a test that had to write into
    /// `~/.victor-effects` to check a path rule would be editing the running
    /// app's configuration.
    func override(_ v: EffectsConfigValues) { values = v }

    var port: UInt16 { values.port }
    var soundsDir: URL { URL(fileURLWithPath: Self.expand(values.soundsDir)) }
    var assetsDir: URL { URL(fileURLWithPath: Self.expand(values.assetsDir)) }
    var eventWebhook: String { values.eventWebhook }
    var bluetoothSpeakerNameMatch: String { values.bluetoothSpeakerNameMatch }
    var overlayScreen: String { values.overlayScreen }
    var chargeEmoji: [String] { values.chargeEmoji }

    var soundsDirExists: Bool {
        var isDir: ObjCBool = false
        let ok = FileManager.default.fileExists(atPath: soundsDir.path, isDirectory: &isDir)
        return ok && isDir.boolValue
    }

    /// The live config as JSON, for `/state` and `/config/reload`. Hand-rolled
    /// the way the rest of the HTTP surface is, and routed through
    /// `JSONSerialization` for the string values so a path with a quote in it
    /// cannot break the body it is pasted into.
    var asJSON: String {
        func s(_ v: String) -> String {
            let data = (try? JSONSerialization.data(withJSONObject: [v])) ?? Data()
            let arr = String(data: data, encoding: .utf8) ?? "[\"\"]"
            return String(arr.dropFirst().dropLast())
        }
        let emoji = values.chargeEmoji.map { s($0) }.joined(separator: ",")
        return "{\"port\":\(values.port),\"soundsDir\":\(s(soundsDir.path)),"
            + "\"assetsDir\":\(s(assetsDir.path)),\"eventWebhook\":\(s(values.eventWebhook)),"
            + "\"bluetoothSpeakerNameMatch\":\(s(values.bluetoothSpeakerNameMatch)),"
            + "\"overlayScreen\":\(s(values.overlayScreen)),\"chargeEmoji\":[\(emoji)],"
            + "\"soundsDirExists\":\(soundsDirExists)}"
    }

    static func expand(_ path: String) -> String {
        (path as NSString).expandingTildeInPath
    }

    /// An optional extra asset: `assetsDir/<name>` when the user dropped one
    /// there, else the copy bundled with the app. Returns nil when neither
    /// exists — every caller is expected to degrade quietly, because these six
    /// files are deliberately not in the repo.
    func assetURL(_ name: String) -> URL? {
        let external = assetsDir.appendingPathComponent(name)
        if FileManager.default.fileExists(atPath: external.path) { return external }
        let ns = name as NSString
        let ext = ns.pathExtension
        let base = ns.deletingPathExtension
        if !ext.isEmpty,
           let bundled = Bundle.module.url(forResource: base, withExtension: ext) {
            return bundled
        }
        return nil
    }
}
