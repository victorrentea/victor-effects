import AVFoundation
import CryptoKit
import Foundation

/// A right-click on the whip says the last thank-you out loud, the way its
/// country says it (2026-11-11, Victor: *"ultimul afișat să fie pronunțat
/// corect (ia de pe google …) + să apară țara din care vine"*).
///
/// The voice is Google Translate's TTS, fetched once per phrase and kept in
/// `cacheDir`, so the room never waits on the network after the first whip of
/// the day (`prefetch` runs on `show()`). Nothing of it is committed — this
/// repo is public. Offline, or for a language Google does not speak (Maltese
/// answers 400), macOS's own voice for that language reads it instead.
enum WhipVoice {

    /// The language a phrase is spoken in: its own entry when the flag does
    /// not decide it (three languages under 🇪🇸, French in 🇨🇭), else its flag's.
    static func language(of phrase: String) -> String {
        let (_, iso, words) = WhipPleas.flagged(phrase)
        return languageByWords[key(words)] ?? languageByCountry[iso] ?? "en"
    }

    /// Lookup key for the word tables: lower-case, no punctuation, so
    /// *jiāyóu!* and *jiāyóu* are one entry.
    static func key(_ words: String) -> String {
        String(words.lowercased().unicodeScalars.filter {
            !CharacterSet.punctuationCharacters.contains($0)
        }).trimmingCharacters(in: .whitespaces)
    }

    /// Japanese, Chinese and Indian thank-yous are SHOWN in Latin letters, so
    /// the room can read them (2026-11-11, Victor: *"scrie cu caractere pe
    /// care să le știu"*), but Google reads Latin letters with a foreign
    /// accent — so it is handed the native script instead.
    static let nativeScript: [String: String] = [
        "arigatō": "ありがとう", "arigato": "ありがとう",
        "dōmo arigatō": "どうもありがとう", "domo arigato": "どうもありがとう",
        "otsukaresama": "おつかれさま",
        "xièxie": "谢谢", "xiexie": "谢谢",
        "jiāyóu": "加油", "jiayou": "加油",
        "xīnkǔ le": "辛苦了", "xinku le": "辛苦了",
        "dhanyavaad": "धन्यवाद", "shukriya": "शुक्रिया",
        "jaldi jaldi": "जल्दी जल्दी", "nandri": "நன்றி",
    ]

    static let languageByWords: [String: String] = [
        "gràcies": "ca", "moltes gràcies": "ca", "milesker": "eu", "eskerrik asko": "eu",
        "merci": "fr", "merci vielmal": "de-CH", "grazzi": "mt",
        "go raibh maith agat": "ga", "nandri": "ta",
    ]

    /// Google Translate `tl` codes, by ISO 3166 country.
    static let languageByCountry: [String: String] = [
        "AT": "de", "BE": "nl", "BG": "bg", "CH": "de", "CN": "zh-CN", "CY": "el",
        "CZ": "cs", "DE": "de", "DK": "da", "EE": "et", "ES": "es", "FI": "fi",
        "FR": "fr", "GB": "en-GB", "GR": "el", "HR": "hr", "HU": "hu", "IE": "en-IE",
        "IN": "hi", "IS": "is", "IT": "it", "JP": "ja", "LI": "de", "LT": "lt",
        "LU": "lb", "LV": "lv", "MD": "ro", "MT": "mt", "NL": "nl", "NO": "no",
        "PL": "pl", "PT": "pt-PT", "RO": "ro", "SE": "sv", "SI": "sl", "SK": "sk",
        "TW": "zh-TW", "US": "en-US",
    ]

    /// Where each phrase's mp3 is kept between launches.
    static var cacheDir: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".victor-effects/voice", isDirectory: true)
    }

    /// The words alone go to Google — never the flag — in their native
    /// script when they are shown romanised (`nativeScript`).
    static func spokenText(of phrase: String) -> String {
        let words = WhipPleas.flagged(phrase).words.trimmingCharacters(in: .whitespaces)
        return nativeScript[key(words)] ?? words
    }

    static func cacheURL(for phrase: String) -> URL {
        let key = language(of: phrase) + "|" + spokenText(of: phrase)
        let hash = SHA256.hash(data: Data(key.utf8)).prefix(8).map { String(format: "%02x", $0) }.joined()
        return cacheDir.appendingPathComponent("\(language(of: phrase))-\(hash).mp3")
    }

    static func googleURL(for phrase: String) -> URL? {
        var c = URLComponents(string: "https://translate.google.com/translate_tts")
        c?.queryItems = [
            .init(name: "ie", value: "UTF-8"), .init(name: "client", value: "tw-ob"),
            .init(name: "tl", value: language(of: phrase)), .init(name: "q", value: spokenText(of: phrase)),
        ]
        return c?.url
    }

    // MARK: - Fetching

    private static var prefetched = false

    /// Fetches every phrase not yet cached, one after the other, in the
    /// background. Once per launch; a failed one is simply tried again on
    /// the right-click that needs it.
    static func prefetch(_ phrases: [String] = WhipPleas.phrases) {
        guard !prefetched else { return }
        prefetched = true
        let missing = phrases.filter { !FileManager.default.fileExists(atPath: cacheURL(for: $0).path) }
        guard !missing.isEmpty else { return }
        DispatchQueue.global(qos: .utility).async {
            for phrase in missing {
                let done = DispatchSemaphore(value: 0)
                fetch(phrase) { _ in done.signal() }
                _ = done.wait(timeout: .now() + 10)
            }
        }
    }

    /// Downloads one phrase into the cache; `completion(url)` with nil on any failure.
    static func fetch(_ phrase: String, completion: @escaping (URL?) -> Void) {
        let target = cacheURL(for: phrase)
        guard let url = googleURL(for: phrase) else { completion(nil); return }
        var request = URLRequest(url: url, timeoutInterval: 4)
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        URLSession.shared.dataTask(with: request) { data, response, _ in
            guard let data, data.count > 1000,
                  (response as? HTTPURLResponse)?.statusCode == 200 else {
                completion(nil); return
            }
            do {
                try FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
                try data.write(to: target, options: .atomic)
                completion(target)
            } catch {
                completion(nil)
            }
        }.resume()
    }

    // MARK: - Speaking

    private static var player: AVAudioPlayer?
    private static let synthesizer = AVSpeechSynthesizer()

    /// Says `phrase`: the cached Google voice, else fetched now, else macOS's.
    /// A new right-click cuts the previous one short.
    static func speak(_ phrase: String) {
        player?.stop()
        synthesizer.stopSpeaking(at: .immediate)
        let cached = cacheURL(for: phrase)
        if FileManager.default.fileExists(atPath: cached.path) {
            play(cached, fallback: phrase)
            return
        }
        fetch(phrase) { url in
            DispatchQueue.main.async {
                if let url { play(url, fallback: phrase) } else { speakLocally(phrase) }
            }
        }
    }

    private static func play(_ url: URL, fallback phrase: String) {
        do {
            let p = try SoundManager.player(contentsOf: url)
            p.volume = SoundManager.shared.currentTabletVolume
            p.prepareToPlay()
            p.play()
            player = p
        } catch {
            speakLocally(phrase)
        }
    }

    private static func speakLocally(_ phrase: String) {
        let utterance = AVSpeechUtterance(string: spokenText(of: phrase))
        utterance.voice = AVSpeechSynthesisVoice(language: language(of: phrase))
        utterance.volume = SoundManager.shared.currentTabletVolume
        synthesizer.speak(utterance)
    }

    // MARK: - Country

    /// The country under an explained thank-you, in English: the room is
    /// rarely Romanian-only.
    static func countryName(of phrase: String) -> String? {
        let iso = WhipPleas.flagged(phrase).iso
        guard iso.count == 2 else { return nil }
        return Locale(identifier: "en").localizedString(forRegionCode: iso)
    }
}
