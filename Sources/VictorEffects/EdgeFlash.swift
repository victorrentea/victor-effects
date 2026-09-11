import AppKit
import QuartzCore

/// A coloured border that fades around the edges of a screen — the visual half
/// of "the tablet just talked to the Mac" (`/effect/green-flash`).
///
/// This is the third of `ScreenCaptureFlash` that the effects app actually uses.
/// The screenshot app keeps the rest: the camera glyph, the cursor marker, and
/// the suppression depth that stops a flash from photobombing an interactive
/// crop. None of those have a caller here, and carrying them across would have
/// made two copies of a suppression counter that only one process can honour.
enum EdgeFlash {
    private static var activePanels: [NSPanel] = []

    /// The screen the effects live on. Kept under the old name because the
    /// moved code asks the flash for it in a few places.
    static var builtInScreen: NSScreen? { Screens.overlayScreen() }

    static func cancelAll() {
        for panel in activePanels { panel.orderOut(nil) }
        activePanels.removeAll()
    }

    static func flash(on screen: NSScreen,
                      duration: CFTimeInterval = 1.5,
                      thickness: CGFloat = 30,
                      color: NSColor = .systemYellow) {
        let panel = NSPanel(
            contentRect: screen.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.maximumWindow)))
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]

        let size = screen.frame.size
        let view = NSView(frame: NSRect(origin: .zero, size: size))
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.clear.cgColor
        for edge in edgeGradients(size: size, thickness: thickness, color: color) {
            view.layer?.addSublayer(edge)
        }

        panel.contentView = view
        panel.setFrame(screen.frame, display: true)
        panel.orderFrontRegardless()
        activePanels.append(panel)

        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 1.0
        fade.toValue = 0.0
        fade.duration = duration
        fade.timingFunction = CAMediaTimingFunction(name: .linear)
        fade.fillMode = .forwards
        fade.isRemovedOnCompletion = false
        view.layer?.add(fade, forKey: "fade")

        // The flash takes itself down. Nothing outside this process is allowed
        // to be the reason a panel disappears (see the self-termination rule).
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
            panel.orderOut(nil)
            activePanels.removeAll { $0 === panel }
        }
    }

    /// Four bands hugging the edges of `size`, each solid on its outer edge and
    /// fading to nothing inward.
    private static func edgeGradients(size: CGSize, thickness: CGFloat, color: NSColor) -> [CAGradientLayer] {
        let solid = color.cgColor
        let clear = color.withAlphaComponent(0).cgColor

        func band(_ frame: CGRect, from: CGPoint, to: CGPoint) -> CAGradientLayer {
            let layer = CAGradientLayer()
            layer.frame = frame
            layer.colors = [solid, clear]
            layer.startPoint = from
            layer.endPoint = to
            return layer
        }

        return [
            // Top: solid at the top → clear downward
            band(CGRect(x: 0, y: size.height - thickness, width: size.width, height: thickness),
                 from: CGPoint(x: 0.5, y: 1.0), to: CGPoint(x: 0.5, y: 0.0)),
            // Bottom: solid at the bottom → clear upward
            band(CGRect(x: 0, y: 0, width: size.width, height: thickness),
                 from: CGPoint(x: 0.5, y: 0.0), to: CGPoint(x: 0.5, y: 1.0)),
            // Left: solid at the left → clear rightward
            band(CGRect(x: 0, y: 0, width: thickness, height: size.height),
                 from: CGPoint(x: 0.0, y: 0.5), to: CGPoint(x: 1.0, y: 0.5)),
            // Right: solid at the right → clear leftward
            band(CGRect(x: size.width - thickness, y: 0, width: thickness, height: size.height),
                 from: CGPoint(x: 1.0, y: 0.5), to: CGPoint(x: 0.0, y: 0.5)),
        ]
    }
}
