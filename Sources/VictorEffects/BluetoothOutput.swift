import AVFoundation
import CoreAudio
import Foundation

/// Shared helpers describing the current default audio **output** device, plus
/// an inaudible "wake" tone used to warm a Bluetooth A2DP link before a real
/// sound so its start isn't clipped.
///
/// Bluetooth output has a startup lag (the codec/amp must spin up), which both
/// truncates the leading edge of a sound and pushes the audio late relative to
/// any on-screen animation. The companion LaunchBreak tablet already
/// compensates for this on its own output (its `BT_WAKE_MS`); these helpers let
/// the Mac do the *same thing* keyed on the Mac's own output, sharing the
/// `bluetoothCompensationMs` value from `sound-timing.json` (see
/// `SoundTimingConfig`). On built-in/wired output everything is a no-op.
enum BluetoothOutput {

    /// Substring (case-insensitive) a Bluetooth output's name must contain to
    /// be "the speakers" — the boxes that standby-mute and need the keep-alive
    /// tone. Configured, and **empty by default**: naming one brand here would
    /// make every other Mac play an inaudible tone forever at a device it was
    /// never meant to hold awake.
    static var speakerNameMatch: String { EffectsConfig.shared.bluetoothSpeakerNameMatch }

    // MARK: - Output device transport

    /// `(isBluetooth, deviceName)` for the current default output device.
    static func defaultOutput() -> (isBluetooth: Bool, name: String) {
        let sys = AudioObjectID(kAudioObjectSystemObject)
        var devAddr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var devID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(sys, &devAddr, 0, nil, &size, &devID) == noErr, devID != 0 else {
            return (false, "?")
        }

        var transAddr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var transport: UInt32 = 0
        var tsize = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(devID, &transAddr, 0, nil, &tsize, &transport) == noErr else {
            return (false, deviceName(devID))
        }
        let isBT = transport == kAudioDeviceTransportTypeBluetooth
            || transport == kAudioDeviceTransportTypeBluetoothLE
        return (isBT, deviceName(devID))
    }

    /// Whether the current default output device is a Bluetooth device. Cheap
    /// CoreAudio property read; safe to call on the main thread per effect.
    static var isDefaultOutputBluetooth: Bool { defaultOutput().isBluetooth }

    static func deviceName(_ devID: AudioDeviceID) -> String {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var nameSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(devID, &addr, 0, nil, &nameSize) == noErr else { return "?" }
        var n: Unmanaged<CFString>?
        guard AudioObjectGetPropertyData(devID, &addr, 0, nil, &nameSize, &n) == noErr else { return "?" }
        return (n?.takeRetainedValue() as String?) ?? "?"
    }

    // MARK: - Device list / default-output selection

    /// One entry per audio device that can play sound.
    struct OutputDevice {
        let id: AudioDeviceID
        let name: String
        let isBluetooth: Bool
    }

    /// Every device with at least one output channel, in CoreAudio's order.
    /// Used to spot a Bluetooth speaker appearing in (or vanishing from) the
    /// device list — a BT speaker is only listed while it is *connected*.
    static func outputDevices() -> [OutputDevice] {
        let sys = AudioObjectID(kAudioObjectSystemObject)
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(sys, &addr, 0, nil, &size) == noErr else { return [] }
        let count = Int(size) / MemoryLayout<AudioDeviceID>.size
        guard count > 0 else { return [] }
        var ids = [AudioDeviceID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(sys, &addr, 0, nil, &size, &ids) == noErr else { return [] }
        return ids.compactMap { id in
            guard hasOutputChannels(id) else { return nil }
            return OutputDevice(id: id, name: deviceName(id), isBluetooth: isBluetooth(id))
        }
    }

    /// Whether `id` exposes any output channel (a Bluetooth headset also
    /// registers an input-only HFP device we must not select as output).
    private static func hasOutputChannels(_ id: AudioDeviceID) -> Bool {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &addr, 0, nil, &size) == noErr, size > 0 else { return false }
        let buf = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { buf.deallocate() }
        guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, buf) == noErr else { return false }
        let list = UnsafeMutableAudioBufferListPointer(buf.assumingMemoryBound(to: AudioBufferList.self))
        return list.contains { $0.mNumberChannels > 0 }
    }

    private static func isBluetooth(_ id: AudioDeviceID) -> Bool {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var transport: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &transport) == noErr else { return false }
        return transport == kAudioDeviceTransportTypeBluetooth
            || transport == kAudioDeviceTransportTypeBluetoothLE
    }

    /// The current default output device's id, or 0 if unreadable.
    static func defaultOutputID() -> AudioDeviceID {
        let sys = AudioObjectID(kAudioObjectSystemObject)
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var devID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(sys, &addr, 0, nil, &size, &devID) == noErr else { return 0 }
        return devID
    }

    /// Make `id` the macOS default output device (what the Sound menu calls
    /// the output). Returns whether CoreAudio accepted the write — a device
    /// that has just appeared but isn't ready yet answers with an error, which
    /// is why the caller retries.
    @discardableResult
    static func setDefaultOutput(_ id: AudioDeviceID) -> Bool {
        let sys = AudioObjectID(kAudioObjectSystemObject)
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var dev = id
        let size = UInt32(MemoryLayout<AudioDeviceID>.size)
        return AudioObjectSetPropertyData(sys, &addr, 0, nil, size, &dev) == noErr
    }

    // MARK: - A2DP wake tone

    /// Held strong while it plays so it isn't deallocated mid-playback. Main
    /// thread only (AVAudioPlayer is not thread-safe).
    private static var wakePlayer: AVAudioPlayer?
    /// Cache the generated WAV per duration so a burst of effects doesn't
    /// re-synthesize the same samples.
    private static var cachedWav: (seconds: Double, data: Data)?

    /// Play an inaudible tone of `seconds` length on the current default output
    /// to warm the Bluetooth A2DP link, so a real sound played right after it
    /// isn't clipped during codec/amp spin-up. No-op for `seconds <= 0`. Must be
    /// called on the main thread.
    static func playWakeTone(seconds: Double) {
        guard seconds > 0 else { return }
        let data: Data
        if let c = cachedWav, abs(c.seconds - seconds) < 0.001 {
            data = c.data
        } else {
            data = makeSilentToneWav(seconds: seconds)
            cachedWav = (seconds, data)
        }
        do {
            let p = try AVAudioPlayer(data: data)
            p.volume = 1.0  // amplitude is baked into the samples (≈ -56 dBFS)
            p.prepareToPlay()
            wakePlayer = p
            p.play()
        } catch {
            overlayError("BT wake tone failed: \(error)")
        }
    }

    // MARK: - Continuous A2DP warm (interactive features)

    /// Looping near-silent player that keeps a Bluetooth A2DP link continuously
    /// awake while an interactive feature (the 🔥 whip) is on screen, so a
    /// crack/"splash" fired at any instant plays with **no amp spin-up lag**.
    /// That is what lets those cracks be played WITHOUT the usual start delay —
    /// the sound stays in sync with the on-screen crack instead of trailing it
    /// by `bluetoothCompensationMs`. Main thread only (AVAudioPlayer isn't
    /// thread-safe).
    private static var warmPlayer: AVAudioPlayer?

    /// Start the continuous warm tone **iff** the current default output is
    /// Bluetooth. Idempotent (a second call while already warming is a no-op)
    /// and a no-op on built-in/wired output. Pair every call with
    /// `stopContinuousWarm()`.
    static func startContinuousWarm() {
        guard isDefaultOutputBluetooth else { return }
        if warmPlayer?.isPlaying == true { return }
        do {
            // A 2s near-silent loop; each end fades to zero so the loop
            // boundary is click-free and the ≈ -56 dBFS tone stays inaudible.
            let p = try AVAudioPlayer(data: makeSilentToneWav(seconds: 2.0))
            p.numberOfLoops = -1
            p.volume = 1.0  // amplitude is baked into the samples
            p.prepareToPlay()
            warmPlayer = p
            p.play()
        } catch {
            overlayError("BT continuous warm failed: \(error)")
        }
    }

    /// Stop the continuous warm tone (safe if it isn't running).
    static func stopContinuousWarm() {
        warmPlayer?.stop()
        warmPlayer = nil
    }

    // MARK: - Tone generation

    /// Build a mono 16-bit PCM WAV of a very quiet sine burst with 10ms fades
    /// (no click). Amplitude ≈ -56 dBFS: real PCM energy that keeps a Bluetooth
    /// stream/amp alive, yet inaudible in a room. Shared by `playWakeTone` and
    /// `BluetoothKeepAlive`.
    static func makeSilentToneWav(seconds: Double) -> Data {
        let sampleRate = 44100
        let frames = max(1, Int(Double(sampleRate) * seconds))
        let amplitude = 0.0015  // ≈ -56 dBFS
        let freq = 220.0
        let fade = min(frames / 2, Int(0.01 * Double(sampleRate)))  // 10ms fade in/out

        var samples = [Int16](repeating: 0, count: frames)
        for i in 0..<frames {
            var a = amplitude
            if fade > 0 {
                if i < fade {
                    a *= Double(i) / Double(fade)
                } else if i >= frames - fade {
                    a *= Double(frames - i) / Double(fade)
                }
            }
            let v = sin(2.0 * Double.pi * freq * Double(i) / Double(sampleRate)) * a
            samples[i] = Int16((max(-1.0, min(1.0, v)) * 32767.0).rounded())
        }

        let bytesPerSample = 2
        let dataSize = frames * bytesPerSample
        let byteRate = sampleRate * bytesPerSample

        var d = Data()
        func appendLE32(_ v: UInt32) { var x = v.littleEndian; withUnsafeBytes(of: &x) { d.append(contentsOf: $0) } }
        func appendLE16(_ v: UInt16) { var x = v.littleEndian; withUnsafeBytes(of: &x) { d.append(contentsOf: $0) } }

        d.append(contentsOf: Array("RIFF".utf8))
        appendLE32(UInt32(36 + dataSize))
        d.append(contentsOf: Array("WAVE".utf8))
        d.append(contentsOf: Array("fmt ".utf8))
        appendLE32(16)                       // PCM fmt chunk size
        appendLE16(1)                        // audio format = PCM
        appendLE16(1)                        // channels = mono
        appendLE32(UInt32(sampleRate))
        appendLE32(UInt32(byteRate))
        appendLE16(UInt16(bytesPerSample))   // block align
        appendLE16(16)                       // bits per sample
        d.append(contentsOf: Array("data".utf8))
        appendLE32(UInt32(dataSize))
        for s in samples {
            var x = s.littleEndian
            withUnsafeBytes(of: &x) { d.append(contentsOf: $0) }
        }
        return d
    }
}
