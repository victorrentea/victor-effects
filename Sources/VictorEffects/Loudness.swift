import Accelerate
import AVFoundation
import Foundation

/// 📏 EBU R128 **short-term loudness** (ITU-R BS.1770: K-weighting, 3 s window,
/// LUFS), and the one number the ▲ on the tablet's volume bar is built from:
/// the clip's LOUDEST 3 s — its *maximum* short-term loudness.
///
/// Not the sample peak: a clip that peaks at 0 dBFS for one click is not loud,
/// and a mastered song held at −1 dBFS for a minute is. Not the integrated
/// loudness either: every soundboard mp3 is already normalised to −14 LUFS
/// integrated, and still some of them make the room flinch — the loudest
/// stretch is what they flinch at.
///
/// Measured the way `ffmpeg -af ebur128` measures `S`, so the two can be
/// compared (`LoudnessTests` does, within 0.5 LU), with two choices of ours:
///
/// - **A clip shorter than 3 s is measured over its own length**, not padded
///   with silence (ffmpeg prints no `S` at all for it): the window is
///   min(3 s, clip). Padding read a 1 s blast ~5 dB quieter than it is, and
///   recommended turning eighteen short tiles UP (Victor, 2026-11-09).
/// - **Mono counts as dual-mono** (ffmpeg's `dualmono=true`): a mono file is
///   played on both speakers, so it is as loud as the stereo file with the same
///   signal on both channels, not 3 dB quieter.
enum Loudness {
    /// The short-term window and its hop, as in EBU Tech 3341.
    static let window: Double = 3.0
    static let hop: Double = 0.1

    enum Failure: Error { case unreadable(String) }

    /// The K-weighting filter for `sampleRate`, as two biquad sections in
    /// `vDSP_biquadD` order (`b0 b1 b2 a1 a2` each): the high-shelf "head"
    /// stage, then the RLB high-pass. BS.1770 tabulates them for 48 kHz only;
    /// these are the analog prototypes it was derived from (libebur128's
    /// derivation, which is also ffmpeg's), so 44.1 kHz gets its own exact filter.
    static func kWeighting(sampleRate fs: Double) -> [Double] {
        var f0 = 1681.974450955533
        let G = 3.999843853973347
        var Q = 0.7071752369554196
        var K = tan(Double.pi * f0 / fs)
        let Vh = pow(10, G / 20)
        let Vb = pow(Vh, 0.4996667741545416)
        var a0 = 1 + K / Q + K * K
        let shelf = [(Vh + Vb * K / Q + K * K) / a0, 2 * (K * K - Vh) / a0, (Vh - Vb * K / Q + K * K) / a0,
                     2 * (K * K - 1) / a0, (1 - K / Q + K * K) / a0]
        f0 = 38.13547087602444
        Q = 0.5003270373238773
        K = tan(Double.pi * f0 / fs)
        a0 = 1 + K / Q + K * K
        let highPass = [1.0, -2.0, 1.0, 2 * (K * K - 1) / a0, (1 - K / Q + K * K) / a0]
        return shelf + highPass
    }

    /// The loudest short-term loudness (LUFS) of `channels` (each a run of
    /// samples at `sampleRate`), or nil for silence (under −70 LUFS).
    static func maxShortTerm(channels: [[Float]], sampleRate fs: Double) -> Double? {
        guard let n = channels.first?.count, n > 0, fs > 0 else { return nil }
        let block = max(1, Int((fs * hop).rounded()))
        let blocksPerWindow = Int((window / hop).rounded())
        let fullBlocks = n / block
        // Per 100 ms block: the K-weighted energy summed over the channels.
        var energy = [Double](repeating: 0, count: fullBlocks + 1)
        let weight: Double = channels.count == 1 ? 2 : 1    // dual-mono
        let coeffs = kWeighting(sampleRate: fs)
        var x = [Double](repeating: 0, count: n)
        var y = [Double](repeating: 0, count: n)
        for ch in channels {
            vDSP_vspdp(ch, 1, &x, 1, vDSP_Length(n))
            guard let setup = vDSP_biquad_CreateSetupD(coeffs, 2) else { return nil }
            var delay = [Double](repeating: 0, count: 2 * 2 + 2)
            vDSP_biquadD(setup, &delay, x, 1, &y, 1, vDSP_Length(n))
            vDSP_biquad_DestroySetupD(setup)
            y.withUnsafeBufferPointer { yp in
                for b in 0...fullBlocks {
                    let start = b * block
                    let len = min(block, n - start)
                    guard len > 0 else { continue }
                    var s = 0.0
                    vDSP_svesqD(yp.baseAddress! + start, 1, &s, vDSP_Length(len))
                    energy[b] += weight * s
                }
            }
        }
        let windowSamples = Double(blocksPerWindow * block)
        var best = 0.0
        if fullBlocks < blocksPerWindow {
            // Shorter than the window: the window is the clip itself.
            best = energy.reduce(0, +) / Double(n)
        } else {
            var running = energy[0..<blocksPerWindow].reduce(0, +)
            best = running
            for i in blocksPerWindow..<fullBlocks {
                running += energy[i] - energy[i - blocksPerWindow]
                best = max(best, running)
            }
            best /= windowSamples
        }
        guard best > 0 else { return nil }
        let lufs = -0.691 + 10 * log10(best)
        // BS.1770's absolute gate: below −70 LUFS is silence (tile #34's mp3 is a
        // −91 dB placeholder — its cry is played by the effect, not the file).
        return lufs < -70 ? nil : lufs
    }

    /// Decoded audio of `url` — every channel at the file's own rate — between
    /// `start` and `end` seconds (nil = to the end). nil when the file has no
    /// audio track at all (two of the video snippets are silent by design).
    static func decode(_ url: URL, start: Double = 0, end: Double? = nil) throws -> (channels: [[Float]], sampleRate: Double)? {
        let asset = AVURLAsset(url: url)
        guard let track = asset.tracks(withMediaType: .audio).first else {
            if FileManager.default.fileExists(atPath: url.path) { return nil }
            throw Failure.unreadable("no such file: \(url.path)")
        }
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
        ])
        reader.add(output)
        let from = CMTime(seconds: max(0, start), preferredTimescale: 44100)
        let length = end.map { CMTime(seconds: max(0, $0 - max(0, start)), preferredTimescale: 44100) } ?? .positiveInfinity
        reader.timeRange = CMTimeRange(start: from, duration: length)
        guard reader.startReading() else {
            throw Failure.unreadable("\(url.lastPathComponent): \(reader.error?.localizedDescription ?? "cannot read")")
        }
        var interleaved: [Float] = []
        var channelCount = 0
        var rate = 0.0
        while let buffer = output.copyNextSampleBuffer() {
            if channelCount == 0, let desc = CMSampleBufferGetFormatDescription(buffer),
               let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(desc)?.pointee {
                channelCount = Int(asbd.mChannelsPerFrame)
                rate = asbd.mSampleRate
            }
            guard let blockBuffer = CMSampleBufferGetDataBuffer(buffer) else { continue }
            let bytes = CMBlockBufferGetDataLength(blockBuffer)
            var chunk = [Float](repeating: 0, count: bytes / MemoryLayout<Float>.size)
            chunk.withUnsafeMutableBytes { raw in
                _ = CMBlockBufferCopyDataBytes(blockBuffer, atOffset: 0, dataLength: bytes, destination: raw.baseAddress!)
            }
            interleaved.append(contentsOf: chunk)
        }
        if reader.status == .failed {
            throw Failure.unreadable("\(url.lastPathComponent): \(reader.error?.localizedDescription ?? "decode failed")")
        }
        guard channelCount > 0, rate > 0 else { return ([[]], 44100) }
        let frames = interleaved.count / channelCount
        var channels: [[Float]] = []
        interleaved.withUnsafeBufferPointer { src in
            for c in 0..<channelCount {
                var ch = [Float](repeating: 0, count: frames)
                // Strided copy out of the interleaved run: one channel at a time.
                cblas_scopy(Int32(frames), src.baseAddress! + c, Int32(channelCount), &ch, 1)
                channels.append(ch)
            }
        }
        return (channels, rate)
    }

    /// Max short-term loudness of a file (or of its `start…end` window).
    /// `.some(nil)` = the file is silent or has no audio track; throws when it
    /// cannot be read at all — that is the case the coverage test fails on.
    static func maxShortTerm(of url: URL, start: Double = 0, end: Double? = nil) throws -> Double? {
        guard let pcm = try decode(url, start: start, end: end) else { return nil }
        return maxShortTerm(channels: pcm.channels, sampleRate: pcm.sampleRate)
    }
}
