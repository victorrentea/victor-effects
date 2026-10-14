import Foundation

/// The app's own images and sounds — `Sources/VictorEffects/Resources`.
///
/// **Never `Bundle.module` directly** (2026-10-14). SwiftPM's generated
/// accessor looks in exactly two places: next to the `.app` (its root, outside
/// `Contents/`, where any file is unsealed content and costs the signing
/// identity — see docs/deployment.md) and an **absolute** path into the
/// `.build/` folder of the checkout that built it. An `.app` copied to any
/// other Mac has neither, and the accessor's answer to that is `fatalError` —
/// the first effect that wants a picture kills the app. `build-app.sh`
/// therefore copies the bundle into `Contents/Resources/`, which is sealed and
/// travels with the app; the SwiftPM accessor stays the fallback for
/// `swift run` and the tests.
enum EffectsResources {
    static let bundleName = "VictorEffects_VictorEffects.bundle"

    static let bundle: Bundle = {
        if let inside = Bundle.main.resourceURL?.appendingPathComponent(bundleName),
           FileManager.default.fileExists(atPath: inside.path),
           let packaged = Bundle(url: inside) {
            return packaged
        }
        return Bundle.module
    }()

    /// **Every image and sound the effects load, by name** (2026-10-14):
    /// `assetsDir/<name>.<ext>` first, then the copy inside the app.
    ///
    /// Most pictures the effects were built with are someone else's work — a
    /// game's sprite, a film still, a GIF off the internet with no licence —
    /// and those left this public repo (`docs/assets-and-licences.md`). They
    /// still work on any Mac that has them in `assetsDir`, and on every other
    /// Mac the lookup answers nil and the effect degrades quietly, the same
    /// contract the large optional assets always had. The bundled copy is the
    /// fallback, so the free ones need nothing in `assetsDir`.
    static func url(_ name: String, _ ext: String) -> URL? {
        let external = EffectsConfig.shared.assetsDir.appendingPathComponent("\(name).\(ext)")
        if FileManager.default.fileExists(atPath: external.path) { return external }
        return bundle.url(forResource: name, withExtension: ext)
            ?? bundle.url(forResource: name, withExtension: ext, subdirectory: "Resources")
    }
}
