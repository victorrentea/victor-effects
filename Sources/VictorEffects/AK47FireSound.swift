import AVFoundation

/// The 🔫 AK-47's fire noise, for as long as the gun is up (2026-09-30,
/// Victor: *"dacă trag un singur foc, să rămână cumva cu ecou. Să se întrerupă
/// brusc sunetul glonțului"*).
///
/// Two paths out of one player node. The **dry** one is the tablet clip
/// itself, straight to the speaker, and it is *cut*, not faded, when the
/// trigger comes up. The **echo** one is a send of the same signal through a
/// delay and a hall reverb, and it is never cut: once the dry noise stops, the
/// room goes on answering for a second or two. That is what makes one short
/// click read as a shot fired somewhere with walls, rather than a blip — the
/// 60 ms fade this replaced turned a single round into a pop with no body.
///
/// The engine runs for the whole session, idle and silent between bursts, so
/// a trigger pull is only a `play()` on a node that is already wired: the
/// noise starts with the finger, like the `AVAudioPlayer` it replaced.
final class AK47FireSound {
    /// The stretch of `22_minigun.mp3` that is pure, uninterrupted fire: the
    /// clip has a lull at ~2.4 s and a spin-down tail after ~5 s, so a held
    /// trigger loops this window instead of the whole file.
    static let fireLoopEnd: Double = 2.35
    /// The echo: one slap back off a far wall, repeating and darkening.
    static let echoDelay: TimeInterval = 0.22
    static let echoFeedback: Float = 40          // percent
    static let echoLowPass: Float = 3500         // Hz — each repeat duller than the last
    /// How loud the echo bus sits under the dry noise. The loop's peaks are
    /// at −8.5 dB, so half again on top of them does not clip.
    static let echoLevel: Float = 0.5

    private let engine = AVAudioEngine()
    private let node = AVAudioPlayerNode()
    private let delay = AVAudioUnitDelay()
    private let reverb = AVAudioUnitReverb()
    private let echoBus = AVAudioMixerNode()
    private let loop: AVAudioPCMBuffer
    private var stopped = false

    init?(url: URL) {
        guard let file = try? AVAudioFile(forReading: url) else { return nil }
        let format = file.processingFormat
        let count = AVAudioFrameCount(min(AVAudioFramePosition(Self.fireLoopEnd * format.sampleRate), file.length))
        guard count > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: count),
              (try? file.read(into: buffer, frameCount: count)) != nil else { return nil }
        loop = buffer

        engine.attach(node)
        engine.attach(delay)
        engine.attach(reverb)
        engine.attach(echoBus)
        // The node feeds both the speaker (dry) and the echo send.
        engine.connect(node, to: [
            AVAudioConnectionPoint(node: engine.mainMixerNode, bus: engine.mainMixerNode.nextAvailableInputBus),
            AVAudioConnectionPoint(node: delay, bus: 0),
        ], fromBus: 0, format: format)
        engine.connect(delay, to: reverb, format: format)
        engine.connect(reverb, to: echoBus, format: format)
        engine.connect(echoBus, to: engine.mainMixerNode, format: format)

        delay.delayTime = Self.echoDelay
        delay.feedback = Self.echoFeedback
        delay.lowPassCutoff = Self.echoLowPass
        delay.wetDryMix = 100                  // the send carries the echo only
        reverb.loadFactoryPreset(.largeHall)
        reverb.wetDryMix = 50
        echoBus.outputVolume = Self.echoLevel
        do { try engine.start() } catch { return nil }
    }

    /// The trigger is pulled: the fire loop from its top, at once.
    func fire() {
        guard !stopped else { return }
        node.stop()
        node.scheduleBuffer(loop, at: nil, options: .loops)
        node.play()
    }

    /// The trigger is up: the dry noise stops dead, the echo rings on.
    func cut() {
        guard !stopped else { return }
        node.stop()
    }

    /// Session over: everything goes, echo included. Idempotent.
    func stop() {
        guard !stopped else { return }
        stopped = true
        node.stop()
        engine.stop()
    }
}
