import AVFoundation

/// The 🪚 chainsaw's engine, for as long as the saw is up: it idles on its own
/// and screams only while the button is held (2026-09-23, Victor: *"să sune
/// totul în buclă, iar când apăs, să se audă zgomotul mai intens — nu doar
/// bør bør bør, ci vzzzi mai tare"*).
///
/// Both noises are cut out of `18_chainsaw.mp3` itself, which already holds the
/// whole machine in six seconds: a pull-start, a low idle and a full-throttle
/// rev. Two player nodes run side by side for the whole session, each looping
/// its own stretch, and the button only moves their volumes — so a press is
/// heard the instant it lands, with no file to open and no player to start.
///
/// Not an `AVAudioPlayer` with a `currentTime` rewind (the AK-47's trick): a
/// rewind is a jump in the waveform, and a chainsaw idles for minutes, not for
/// the two seconds a trigger is held. A looping PCM buffer with its seam
/// crossfaded never clicks, however long it runs.
final class ChainsawSound {
    /// The stretches of `18_chainsaw.mp3`, in seconds, read off its RMS in
    /// 0.1 s windows: pull-start 0–1.7 (peaks −12 dB), idle 1.7–2.7 (a steady
    /// −30 dB), a rev-up at 2.8, full throttle 3.1–5.8 (a steady −16 dB, peaks
    /// −2.5 dB), spin-down after 5.9.
    static let idleRange = (start: 1.7, end: 2.7)
    static let revRange = (start: 3.1, end: 5.8)
    /// Length of the blend at each loop's seam.
    static let seamCrossfade = 0.12
    /// The rev is played a little fast: +1.3 semitones turns the recorded
    /// throttle into the higher, angrier whine of a blade that is biting. It
    /// is already 14 dB over the idle; with peaks at −2.5 dB there is no
    /// headroom for "louder" by gain, so the extra intensity comes from pitch.
    static let revRate: Float = 1.08
    /// The throttle opens fast and closes slowly: a saw winds down, it does not
    /// switch off.
    static let attack = 0.06
    static let release = 0.3

    private let engine = AVAudioEngine()
    private let idleNode = AVAudioPlayerNode()
    private let revNode = AVAudioPlayerNode()
    private let varispeed = AVAudioUnitVarispeed()
    private var throttle: Float = 0      // 0 = idling, 1 = cutting
    private var stopped = false

    init?(url: URL) {
        guard let file = try? AVAudioFile(forReading: url) else { return nil }
        let format = file.processingFormat
        guard let intro = Self.read(file, from: 0, to: Self.idleRange.start),
              let idle = Self.seamlessLoop(file, Self.idleRange.start, Self.idleRange.end),
              let rev = Self.seamlessLoop(file, Self.revRange.start, Self.revRange.end) else { return nil }

        engine.attach(idleNode)
        engine.attach(revNode)
        engine.attach(varispeed)
        engine.connect(idleNode, to: engine.mainMixerNode, format: format)
        engine.connect(revNode, to: varispeed, format: format)
        engine.connect(varispeed, to: engine.mainMixerNode, format: format)
        varispeed.rate = Self.revRate
        revNode.volume = 0

        // The pull-start once, then the idle for good. The loop's seam is
        // blended into its TAIL, so it begins on the very sample the intro
        // stops before and the hand-over is as continuous as the wrap.
        idleNode.scheduleBuffer(intro, at: nil, options: [])
        idleNode.scheduleBuffer(idle, at: nil, options: .loops)
        revNode.scheduleBuffer(rev, at: nil, options: .loops)
        do { try engine.start() } catch { return nil }
        idleNode.play()
        revNode.play()
    }

    /// One follow tick: move the throttle toward the button and set both
    /// volumes from it. Equal-power, so the swap has no dip in the middle.
    func tick(cutting: Bool, dt: Double) {
        guard !stopped else { return }
        let step = Float(dt / (cutting ? Self.attack : Self.release))
        throttle = cutting ? min(1, throttle + step) : max(0, throttle - step)
        revNode.volume = sinf(throttle * .pi / 2)
        idleNode.volume = cosf(throttle * .pi / 2)
    }

    /// Fade the whole engine out and let it go. Idempotent.
    func stop(fade: Double) {
        guard !stopped else { return }
        stopped = true
        let steps = max(1, Int(fade * 60))
        let mixer = engine.mainMixerNode
        let from = mixer.outputVolume
        for i in 1...steps {
            DispatchQueue.main.asyncAfter(deadline: .now() + fade * Double(i) / Double(steps)) { [self] in
                mixer.outputVolume = from * Float(steps - i) / Float(steps)
                if i == steps { engine.stop() }
            }
        }
    }

    // MARK: Buffers

    private static func read(_ file: AVAudioFile, from start: Double, to end: Double) -> AVAudioPCMBuffer? {
        let rate = file.processingFormat.sampleRate
        let first = AVAudioFramePosition(start * rate)
        let count = AVAudioFrameCount(max(0, min(AVAudioFramePosition(end * rate), file.length) - first))
        guard count > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: count) else { return nil }
        file.framePosition = first
        do { try file.read(into: buffer, frameCount: count) } catch { return nil }
        return buffer
    }

    /// `start..<end` as a buffer that loops without a seam: its last
    /// `seamCrossfade` seconds fade into the audio that came just BEFORE
    /// `start`, so the final sample leads straight into the first one.
    private static func seamlessLoop(_ file: AVAudioFile, _ start: Double, _ end: Double) -> AVAudioPCMBuffer? {
        guard let src = read(file, from: start - seamCrossfade, to: end),
              let channels = src.floatChannelData else { return nil }
        let rate = file.processingFormat.sampleRate
        let fade = Int(seamCrossfade * rate)
        let length = Int(src.frameLength) - fade
        guard length > fade,
              let out = AVAudioPCMBuffer(pcmFormat: src.format, frameCapacity: AVAudioFrameCount(length)),
              let outChannels = out.floatChannelData else { return nil }
        out.frameLength = AVAudioFrameCount(length)
        for ch in 0..<Int(src.format.channelCount) {
            let s = channels[ch], o = outChannels[ch]
            for j in 0..<length { o[j] = s[fade + j] }
            // Tail j (the last `fade` frames) blends out of the clip's own
            // continuation and into what precedes `start`: at the last frame it
            // IS the sample before the loop's first one.
            for i in 0..<fade {
                let t = Float(i + 1) / Float(fade)
                let j = length - fade + i
                o[j] = s[fade + j] * cosf(t * .pi / 2) + s[i] * sinf(t * .pi / 2)
            }
        }
        return out
    }
}
