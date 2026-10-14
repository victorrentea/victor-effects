import CoreGraphics
import Foundation
import ScreenCaptureKit

/// A screenshot of a display **without the press caption in it**, for the
/// screenshot effects' synchronous captures (`captureBuiltInDisplay` and its
/// fast twin in `EmojiAnimator`).
///
/// Every soundboard press is captioned *before* its effect runs, so a 💀 #39
/// that photographs the screen photographed its own caption, then zoomed the
/// copy under the live one — a 50 % pill shows the giant ghost straight
/// through. Neither `screencapture(1)` nor `CGDisplayCreateImage` can leave a
/// window out; ScreenCaptureKit can.
///
/// Only attempted while a caption is on the glass, so with ✓ Subtitles off —
/// the default — every capture is exactly what it was. Answers nil (meaning
/// "take the ordinary screenshot") on macOS 13, without Screen Recording, when
/// the caption window is not in the window list, or after `timeout`: a ghost
/// caption is a blemish, a frozen effect is a failure.
enum CaptionSafeCapture {
    static let timeout: TimeInterval = 1.0

    /// Blocks the calling thread for the capture (tens of ms with the filter
    /// cached). Safe on any thread: ScreenCaptureKit answers on its own queues.
    static func displayImage(displayID: CGDirectDisplayID) -> CGImage? {
        guard #available(macOS 14.0, *), let caption = CaptionOverlay.onGlassWindowID else { return nil }
        let done = DispatchSemaphore(value: 0)
        let box = ImageBox()
        filter(excluding: caption, displayID: displayID) { filter in
            guard let filter else { done.signal(); return }
            let cfg = SCStreamConfiguration()
            cfg.width = Int(filter.contentRect.width * CGFloat(filter.pointPixelScale))
            cfg.height = Int(filter.contentRect.height * CGFloat(filter.pointPixelScale))
            // As the ordinary captures: never bake a pointer into the picture.
            cfg.showsCursor = false
            cfg.captureResolution = .best
            SCScreenshotManager.captureImage(contentFilter: filter, configuration: cfg) { image, error in
                if image == nil, let error {
                    effectsError("💬 caption-free capture failed: \(error.localizedDescription)")
                }
                box.set(image)
                done.signal()
            }
        }
        guard done.wait(timeout: .now() + timeout) == .success else {
            effectsError("💬 caption-free capture timed out — falling back to the ordinary one")
            return nil
        }
        return box.get()
    }

    private final class ImageBox: @unchecked Sendable {
        private let lock = NSLock()
        private var image: CGImage?
        func set(_ i: CGImage?) { lock.lock(); image = i; lock.unlock() }
        func get() -> CGImage? { lock.lock(); defer { lock.unlock() }; return image }
    }

    /// The filter is built once per caption window and display: the caption
    /// panel is made at launch and reused for every line, so its id is stable,
    /// and `SCContentFilter(display:excludingWindows:)` is evaluated at capture
    /// time — windows opened later are still photographed.
    private static let cacheLock = NSLock()
    private static var cached: (key: String, filter: AnyObject)?

    @available(macOS 14.0, *)
    private static func filter(excluding caption: CGWindowID, displayID: CGDirectDisplayID,
                               _ done: @escaping (SCContentFilter?) -> Void) {
        let key = "\(caption)@\(displayID)"
        cacheLock.lock()
        let hit = cached?.key == key ? cached?.filter as? SCContentFilter : nil
        cacheLock.unlock()
        if let hit { done(hit); return }
        SCShareableContent.getExcludingDesktopWindows(false, onScreenWindowsOnly: true) { content, error in
            guard let content,
                  let display = content.displays.first(where: { $0.displayID == displayID }),
                  let window = content.windows.first(where: { $0.windowID == caption }) else {
                effectsInfo("💬 caption not in the shareable window list — ordinary capture: \(error?.localizedDescription ?? "not listed")")
                done(nil)
                return
            }
            let filter = SCContentFilter(display: display, excludingWindows: [window])
            cacheLock.lock()
            cached = (key, filter)
            cacheLock.unlock()
            done(filter)
        }
    }
}
