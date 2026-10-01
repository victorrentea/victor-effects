import AVFoundation

/// The 🔫 AK-47's fire noise, for as long as the gun is up.
///
/// **Every pull is one whole round** (2026-10-01, Victor: *"trebuie să aud
/// mereu un glonț întreg când apăs o dată pe click"*). The tablet clip is a
/// minigun's roar with no gap between rounds, so the 2026-09-30 design — the
/// loop from its top, stopped dead at the end of the round in flight — made a
/// single click 0.1 s of roar chopped off: a blip, and an echo with almost
/// nothing to ring with. A round is now *built* from that roar: one round's
/// length at full level, then an exponential decay (`shotDecay`) down to
/// silence. It plays on a voice of its own that nothing cuts, so it always
/// ends the way a shot ends.
///
/// A **held** trigger adds the loop on top from the second round on
/// (`sustain`), continuing the clip where the first round's body left it. The
/// release stops the loop at a round boundary and hands over to `tail` — the
/// same roar, decaying from the first sample — so a burst also rings out
/// instead of stopping like a switch.
///
/// Everything dry goes through one bus to the speaker **and** to a send
/// through a delay and a hall reverb, which is never cut: once the dry noise
/// is gone, the room goes on answering for a second or two.
///
/// The engine runs for the whole session, idle and silent between bursts, so
/// a trigger pull is only a `play()` on a node that is already wired.
final class AK47FireSound {
    /// The stretch of `22_minigun.mp3` that is pure, uninterrupted fire: the
    /// clip has a lull at ~2.4 s and a spin-down tail after ~5 s, so a held
    /// trigger loops this window instead of the whole file.
    static let fireLoopEnd: Double = 2.35
    /// One round's body: the cyclic rate's period (600 rpm).
    static let roundLength: Double = 0.1
    /// Time constant of a round's decay. Seven of them (≈ 0.5 s) take it to
    /// −60 dB, where the buffer ends.
    static let shotDecay: Double = 0.07
    static let shotTailLength: Double = 7 * shotDecay
    /// The echo: one slap back off a far wall, repeating and darkening.
    static let echoDelay: TimeInterval = 0.22
    static let echoFeedback: Float = 40          // percent
    static let echoLowPass: Float = 3500         // Hz — each repeat duller than the last
    /// How loud the echo bus sits under the dry noise. The loop's peaks are
    /// at −8.5 dB, so half again on top of them does not clip.
    static let echoLevel: Float = 0.5
    /// Rounds that can ring at once: a tail lasts ~0.6 s and clicks come no
    /// faster than ~6/s, so four voices never steal one that is still sounding.
    static let shotVoices = 4

    /// Envelope of one round at `t` seconds: flat for the body, then decaying.
    /// `body` 0 is the release tail, which starts decaying at once.
    static func shotGain(at t: Double, body: Double) -> Float {
        t < body ? 1 : Float(exp(-(t - body) / shotDecay))
    }

    private let engine = AVAudioEngine()
    private let loopNode = AVAudioPlayerNode()
    private let shotNodes: [AVAudioPlayerNode]
    private var nextVoice = 0
    private let dryBus = AVAudioMixerNode()
    private let delay = AVAudioUnitDelay()
    private let reverb = AVAudioUnitReverb()
    private let echoBus = AVAudioMixerNode()
    private let loop: AVAudioPCMBuffer
    private let shot: AVAudioPCMBuffer
    private let tail: AVAudioPCMBuffer
    private var sustaining = false
    private var stopped = false

    init?(url: URL) {
        guard let file = try? AVAudioFile(forReading: url) else { return nil }
        let format = file.processingFormat
        let rate = format.sampleRate
        let fireFrames = min(AVAudioFramePosition(Self.fireLoopEnd * rate), file.length)
        guard fireFrames > 0,
              let fire = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(fireFrames)),
              (try? file.read(into: fire, frameCount: AVAudioFrameCount(fireFrames))) != nil else { return nil }
        let round = Int(Self.roundLength * rate)
        let tailFrames = Int(Self.shotTailLength * rate)
        guard Int(fire.frameLength) > round + tailFrames,
              let shot = Self.slice(fire, from: 0, count: round + tailFrames, body: Self.roundLength),
              let tail = Self.slice(fire, from: round, count: tailFrames, body: 0),
              let loop = Self.slice(fire, from: round, count: Int(fire.frameLength) - round, body: nil)
        else { return nil }
        self.shot = shot
        self.tail = tail
        self.loop = loop
        shotNodes = (0..<Self.shotVoices).map { _ in AVAudioPlayerNode() }

        engine.attach(dryBus)
        engine.attach(delay)
        engine.attach(reverb)
        engine.attach(echoBus)
        for node in [loopNode] + shotNodes {
            engine.attach(node)
            engine.connect(node, to: dryBus, format: format)
        }
        // The dry bus feeds both the speaker and the echo send.
        engine.connect(dryBus, to: [
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

    /// `count` frames of `source` from `from`, shaped by `shotGain` (`body`
    /// nil: copied as is, for the loop).
    private static func slice(_ source: AVAudioPCMBuffer, from: Int, count: Int,
                              body: Double?) -> AVAudioPCMBuffer? {
        guard count > 0, from + count <= Int(source.frameLength),
              let src = source.floatChannelData,
              let out = AVAudioPCMBuffer(pcmFormat: source.format, frameCapacity: AVAudioFrameCount(count)),
              let dst = out.floatChannelData else { return nil }
        out.frameLength = AVAudioFrameCount(count)
        let rate = source.format.sampleRate
        for ch in 0..<Int(source.format.channelCount) {
            for i in 0..<count {
                let gain = body.map { shotGain(at: Double(i) / rate, body: $0) } ?? 1
                dst[ch][i] = src[ch][from + i] * gain
            }
        }
        return out
    }

    /// The trigger is pulled: one whole round, at once, on a free voice.
    func fire() {
        guard !stopped else { return }
        play(shot)
    }

    /// Still held when the second round goes out: the roar takes over,
    /// looping, until `cut`. Idempotent.
    func sustain() {
        guard !stopped, !sustaining else { return }
        sustaining = true
        loopNode.scheduleBuffer(loop, at: nil, options: .loops)
        loopNode.play()
    }

    /// The trigger is up (at a round boundary): a held burst rings out on the
    /// tail; a single round is already ringing out on its own.
    func cut() {
        guard !stopped, sustaining else { return }
        sustaining = false
        loopNode.stop()
        play(tail)
    }

    private func play(_ buffer: AVAudioPCMBuffer) {
        let node = shotNodes[nextVoice]
        nextVoice = (nextVoice + 1) % shotNodes.count
        node.stop()
        node.scheduleBuffer(buffer, at: nil)
        node.play()
    }

    /// Session over: everything goes, echo included. Idempotent.
    func stop() {
        guard !stopped else { return }
        stopped = true
        loopNode.stop()
        shotNodes.forEach { $0.stop() }
        engine.stop()
    }
}
