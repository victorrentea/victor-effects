// gallery-recorder — the capture half of `tools/record-gallery.sh`.
//
// Why this exists at all: macOS gives a shell script no usable way to record
// video of the desktop any more.
//
//   - `ffmpeg -f avfoundation` has **no screen device** left on this machine
//     (`-list_devices` lists cameras and microphones only) — AVFoundation's
//     screen input was retired in favour of ScreenCaptureKit.
//   - `screencapture -v` answers `capture error The operation could not be
//     completed` when it is started from a script rather than from a Terminal
//     a human is sitting in, and it refuses `-l<windowid>` and `-R<rect>` for
//     video outright (both are image-only flags). Stills work fine; video does
//     not.
//
// So the one capture path that survives is ScreenCaptureKit, and this is the
// smallest wrapper around it that produces an mp4. It is compiled on demand by
// the script with `swiftc` — deliberately NOT a target in Package.swift, so
// building the gallery never rebuilds (or breaks) the app.
//
// Two filters, because the gallery has two audiences:
//
//   --display   the whole overlay screen. Everything the app can draw ends up
//               in the frame, including the four effects that live in their
//               OWN windows (whip, claude-peek, green-flash, the thumbnail
//               panel) and the mouse cursor. The backdrop is whatever
//               is really on screen, which is the point — but it also means the
//               screen is *being recorded*, so the script holds the 🔒 locks.
//
//   --window    one window only (the app's `OverlayPanel`), captured WITH its
//               alpha and composited here over a still `--backdrop` image. The
//               recording then contains none of Victor's own screen, at the
//               price of missing every effect that is not drawn on that panel.
//               `record-gallery.sh` knows which those are and skips them.
//
// Stops on: `--seconds`, a line on stdin, or SIGINT — whichever comes first.
// The stdin stop is what the script uses, because an effect's real length is
// only known once `/state` says it is over.

// AppKit is imported for exactly one line — `NSApplication.shared`, which opens
// the window-server (CGS) connection. Without it ScreenCaptureKit's window
// filter aborts the process outright with `CGS_REQUIRE_INIT`, and so does
// `NSImage(contentsOfFile:)`. Everything else deliberately avoids AppKit:
// images go through ImageIO and text through CoreText, so `--label` keeps
// working in contexts with no window server at all.
import AVFoundation
import AppKit
import CoreImage
import CoreMedia
import CoreText
import ImageIO
import ScreenCaptureKit

// MARK: - Arguments

struct Options {
    var out = ""
    var windowID: CGWindowID?
    var display: String?          // "builtin", "main", or a CGDirectDisplayID
    var backdrop: String?
    var width: Int = 1440         // output width in pixels; height follows the aspect
    var fps: Int32 = 30
    var seconds: Double = 30      // hard cap, so a hung script cannot fill the disk
    var cursor = true
    var label: String?            // label mode: draw this instead of recording
    var sublabel: String?
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("gallery-recorder: \(message)\n".utf8))
    exit(2)
}

/// `x ?? fail(…)` does not typecheck here (`Never` is not a bottom type in
/// argument position), and an unwrap that names the flag beats one that traps.
func need<T>(_ value: T?, _ message: String) -> T {
    guard let value else { fail(message) }
    return value
}

var opts = Options()
var args = Array(CommandLine.arguments.dropFirst())
while let arg = args.first {
    args.removeFirst()
    func value() -> String {
        guard let v = args.first else { fail("\(arg) needs a value") }
        args.removeFirst()
        return v
    }
    switch arg {
    case "--out":      opts.out = value()
    case "--window":   opts.windowID = need(CGWindowID(value()), "--window needs a numeric window id")
    case "--display":  opts.display = value()
    case "--backdrop": opts.backdrop = value()
    case "--width":    opts.width = need(Int(value()), "--width needs a number")
    case "--fps":      opts.fps = need(Int32(value()), "--fps needs a number")
    case "--seconds":  opts.seconds = need(Double(value()), "--seconds needs a number")
    case "--no-cursor": opts.cursor = false
    case "--label":    opts.label = value()
    case "--sublabel": opts.sublabel = value()
    case "--probe":    opts.out = ""      // handled below: list what SCK can see and exit
    default:           fail("unknown argument \(arg)")
    }
}

// MARK: - What ScreenCaptureKit can see

/// `SCShareableContent` is async; everything below wants it as a value, so the
/// one place that waits is here.
func shareableContent() -> SCShareableContent {
    var result: Result<SCShareableContent, Error>?
    let done = DispatchSemaphore(value: 0)
    SCShareableContent.getExcludingDesktopWindows(false, onScreenWindowsOnly: true) { content, error in
        result = content.map(Result.success) ?? .failure(error ?? NSError(domain: "gallery", code: 1))
        done.signal()
    }
    // A missing Screen Recording grant shows up here as a hang, not an error:
    // the system is waiting for a consent dialog nobody is going to click.
    if done.wait(timeout: .now() + 10) == .timedOut {
        fail("ScreenCaptureKit never answered — Screen Recording is almost certainly not granted to the terminal running this")
    }
    switch result! {
    case .success(let c): return c
    case .failure(let e): fail("ScreenCaptureKit: \(e.localizedDescription)")
    }
}

if CommandLine.arguments.contains("--probe") {
    let content = shareableContent()
    for d in content.displays {
        print("display id=\(d.displayID) \(d.width)x\(d.height) builtin=\(CGDisplayIsBuiltin(d.displayID) != 0)")
    }
    for w in content.windows where (w.owningApplication?.applicationName ?? "").contains("Victor Effects") {
        print("window id=\(w.windowID) app=\(w.owningApplication?.applicationName ?? "?") "
              + "title=\(w.title ?? "") frame=\(Int(w.frame.width))x\(Int(w.frame.height)) layer=\(w.windowLayer)")
    }
    exit(0)
}

guard !opts.out.isEmpty else { fail("--out is required") }

// MARK: - Label mode

// The homebrew ffmpeg on this machine is built WITHOUT libfreetype, so
// `drawtext` does not exist and `-vf drawtext=…` dies with "No such filter".
// Rather than make the gallery depend on a rebuilt ffmpeg, the labels are
// rendered here as transparent PNGs and composited with plain `overlay`, which
// every build has. CoreText, not AppKit, for the reason at the top of the file.
func renderLabel(title: String, subtitle: String, width: Int, to path: String) -> Never {
    let scale = 2
    let w = width * scale, h = 150 * scale
    let cs = CGColorSpaceCreateDeviceRGB()
    guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                              space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
        fail("cannot create a label bitmap")
    }
    ctx.clear(CGRect(x: 0, y: 0, width: w, height: h))

    func line(_ text: String, font: String, size: CGFloat, alpha: CGFloat) -> CTLine {
        let f = CTFontCreateWithName(font as CFString, size * CGFloat(scale), nil)
        let color = CGColor(colorSpace: cs, components: [1, 1, 1, alpha])!
        return CTLineCreateWithAttributedString(NSAttributedString(
            string: text,
            attributes: [.font: f, .foregroundColor: color]) as CFAttributedString)
    }
    let titleLine = line(title, font: "HelveticaNeue-Bold", size: 38, alpha: 1)
    let subLine = line(subtitle, font: "Menlo-Regular", size: 20, alpha: 0.72)
    let titleWidth = CTLineGetTypographicBounds(titleLine, nil, nil, nil)
    let subWidth = CTLineGetTypographicBounds(subLine, nil, nil, nil)

    let pad = CGFloat(22 * scale)
    let boxW = min(CGFloat(w) - pad, max(titleWidth, subWidth) + pad * 2)
    let box = CGRect(x: pad, y: pad, width: boxW, height: CGFloat(h) - pad * 2)
    ctx.setFillColor(CGColor(colorSpace: cs, components: [0, 0, 0, 0.62])!)
    ctx.addPath(CGPath(roundedRect: box, cornerWidth: 16 * CGFloat(scale),
                       cornerHeight: 16 * CGFloat(scale), transform: nil))
    ctx.fillPath()

    ctx.textPosition = CGPoint(x: box.minX + pad, y: box.minY + CGFloat(52 * scale))
    CTLineDraw(titleLine, ctx)
    ctx.textPosition = CGPoint(x: box.minX + pad, y: box.minY + CGFloat(20 * scale))
    CTLineDraw(subLine, ctx)

    guard let image = ctx.makeImage(),
          let dest = CGImageDestinationCreateWithURL(
            URL(fileURLWithPath: path) as CFURL, "public.png" as CFString, 1, nil) else {
        fail("cannot write \(path)")
    }
    CGImageDestinationAddImage(dest, image, nil)
    CGImageDestinationFinalize(dest)
    exit(0)
}

if let label = opts.label {
    renderLabel(title: label, subtitle: opts.sublabel ?? "", width: opts.width, to: opts.out)
}

// See the note at the top: this one line is why AppKit is linked. `.prohibited`
// keeps the recorder out of the Dock and out of the ⌘-Tab list — it must not
// become a window that shows up in its own recording.
NSApplication.shared.setActivationPolicy(.prohibited)

let content = shareableContent()

let filter: SCContentFilter
let sourceSize: CGSize
if let wid = opts.windowID {
    guard let window = content.windows.first(where: { $0.windowID == wid }) else {
        fail("window \(wid) is not in ScreenCaptureKit's list — it may have closed, or be on another Space")
    }
    filter = SCContentFilter(desktopIndependentWindow: window)
    sourceSize = window.frame.size
} else {
    let want = opts.display ?? "builtin"
    let display: SCDisplay?
    switch want {
    case "builtin": display = content.displays.first { CGDisplayIsBuiltin($0.displayID) != 0 } ?? content.displays.first
    case "main":    display = content.displays.first { $0.displayID == CGMainDisplayID() } ?? content.displays.first
    default:        display = content.displays.first { String($0.displayID) == want }
    }
    guard let display else { fail("no display matching '\(want)'") }
    filter = SCContentFilter(display: display, excludingWindows: [])
    sourceSize = CGSize(width: display.width, height: display.height)
}

// H.264 wants even dimensions, and a 3456-wide retina capture is four times
// more pixels than a gallery clip needs.
func even(_ v: Int) -> Int { v % 2 == 0 ? v : v - 1 }
let outW = even(min(opts.width, Int(sourceSize.width)))
let outH = even(Int((Double(outW) * sourceSize.height / sourceSize.width).rounded()))

// MARK: - The backdrop (window mode only)

var backdrop: CIImage?
if let path = opts.backdrop {
    guard let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
          let cg = CGImageSourceCreateImageAtIndex(src, 0, nil) else {
        fail("cannot read backdrop image at \(path)")
    }
    // Scaled once, here, so the per-frame work is a single composite.
    let ci = CIImage(cgImage: cg)
    let sx = Double(outW) / ci.extent.width
    let sy = Double(outH) / ci.extent.height
    backdrop = ci.transformed(by: CGAffineTransform(scaleX: sx, y: sy))
}
if backdrop != nil && opts.windowID == nil {
    fail("--backdrop only makes sense with --window: a display capture already has a real backdrop")
}

// MARK: - Writer

let outURL = URL(fileURLWithPath: opts.out)
try? FileManager.default.removeItem(at: outURL)
guard let writer = try? AVAssetWriter(outputURL: outURL, fileType: .mp4) else {
    fail("cannot create \(opts.out)")
}
let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
    AVVideoCodecKey: AVVideoCodecType.h264,
    AVVideoWidthKey: outW,
    AVVideoHeightKey: outH,
    AVVideoCompressionPropertiesKey: [
        AVVideoAverageBitRateKey: outW * outH * 6,   // ~10 Mbit/s at 1440p-wide
        AVVideoMaxKeyFrameIntervalKey: Int(opts.fps),
    ],
])
input.expectsMediaDataInRealTime = true
let adaptor = AVAssetWriterInputPixelBufferAdaptor(
    assetWriterInput: input,
    sourcePixelBufferAttributes: [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        kCVPixelBufferWidthKey as String: outW,
        kCVPixelBufferHeightKey as String: outH,
    ])
writer.add(input)
writer.startWriting()
writer.startSession(atSourceTime: .zero)

let ciContext = CIContext(options: [.useSoftwareRenderer: false])

final class Output: NSObject, SCStreamOutput {
    var firstPTS: CMTime?
    var frames = 0

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, CMSampleBufferGetNumSamples(sampleBuffer) > 0 else { return }
        // SCK also delivers "idle" and "blank" frames (nothing changed on the
        // display). Appending them is harmless but pointless; appending an
        // *incomplete* one writes a torn frame.
        guard let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false)
                as? [[SCStreamFrameInfo: Any]],
              let raw = attachments.first?[.status] as? Int,
              SCFrameStatus(rawValue: raw) == .complete,
              let pixels = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        if firstPTS == nil { firstPTS = pts }
        let stamp = CMTimeSubtract(pts, firstPTS!)
        guard input.isReadyForMoreMediaData else { return }

        if let backdrop {
            // Window mode: the captured frame carries the overlay's alpha, so
            // "over the backdrop" is literally sourceOver.
            guard let pool = adaptor.pixelBufferPool else { return }
            var out: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, pool, &out)
            guard let out else { return }
            var frame = CIImage(cvPixelBuffer: pixels)
            let sx = Double(outW) / frame.extent.width
            let sy = Double(outH) / frame.extent.height
            frame = frame.transformed(by: CGAffineTransform(scaleX: sx, y: sy))
            ciContext.render(frame.composited(over: backdrop), to: out)
            adaptor.append(out, withPresentationTime: stamp)
        } else {
            adaptor.append(pixels, withPresentationTime: stamp)
        }
        frames += 1
    }
}

let config = SCStreamConfiguration()
config.width = outW
config.height = outH
config.minimumFrameInterval = CMTime(value: 1, timescale: opts.fps)
config.queueDepth = 8
config.showsCursor = opts.cursor
config.capturesAudio = false
config.pixelFormat = kCVPixelFormatType_32BGRA
config.scalesToFit = true
if opts.windowID != nil {
    // Transparent, so the composite above sees real alpha rather than black.
    config.backgroundColor = .clear
}

let output = Output()
let stream = SCStream(filter: filter, configuration: config, delegate: nil)
try? stream.addStreamOutput(output, type: .screen, sampleHandlerQueue: DispatchQueue(label: "gallery.capture"))

var stopping = false
func stop(_ reason: String) {
    guard !stopping else { return }
    stopping = true
    stream.stopCapture { _ in
        input.markAsFinished()
        writer.finishWriting {
            FileHandle.standardError.write(Data("gallery-recorder: \(reason), \(output.frames) frames → \(opts.out)\n".utf8))
            exit(output.frames > 0 ? 0 : 3)
        }
    }
}

// `signal(2)` handlers must be capture-free C function pointers, and `stop`
// closes over the writer — so the interrupt goes through GCD instead. The
// `SIG_IGN` is what disarms the default "die immediately" behaviour; without it
// the mp4 would be left unfinalised and unplayable on every Ctrl-C.
let signalSources = [SIGINT, SIGTERM].map { sig -> DispatchSourceSignal in
    signal(sig, SIG_IGN)
    let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
    source.setEventHandler { stop(sig == SIGINT ? "interrupted" : "terminated") }
    source.resume()
    return source
}

stream.startCapture { error in
    if let error { fail("startCapture: \(error.localizedDescription)") }
}

// The script's stop signal: one line on stdin. EOF counts too, so a closed pipe
// ends the recording rather than leaving it running to the cap.
DispatchQueue.global().async {
    _ = readLine(strippingNewline: true)
    DispatchQueue.main.async { stop("stdin") }
}
DispatchQueue.main.asyncAfter(deadline: .now() + opts.seconds) { stop("cap of \(opts.seconds)s") }

RunLoop.main.run()
