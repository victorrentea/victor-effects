import Foundation

/// The three things that can ride the pointer — one at a time.
///
/// Since 2026-10-21 the keys split the job (Victor: *"Control Shift W should
/// change the way of the whip. Control W should toggle it on or off, and it
/// should remember the selection"*): **⌃W** shows or hides the *selected* mode,
/// **⌃⇧W** moves the selection on to the next one (and shows it, so the change
/// is seen). Whatever was shown last — by a key, a menu row or
/// `/effect/<name>` — is the selection the next ⌃W brings back.
enum PointerMode: String, CaseIterable {
    case whip, pray, snap

    /// 🔥 → 🙏 → 🫰 → 🔥 …
    var next: PointerMode {
        let all = Self.allCases
        return all[(all.firstIndex(of: self)! + 1) % all.count]
    }
}

/// `PointerMode` with `UserDefaults` behind it — the app is rebuilt and
/// restarted several times an hour, and a selection a `pkill` forgets is not a
/// selection (the same reasoning as `PeekMascotStore`).
enum PointerModeStore {
    private static let kMode = "PointerMode.selected"

    static var selected: PointerMode {
        get { UserDefaults.standard.string(forKey: kMode).flatMap(PointerMode.init(rawValue:)) ?? .whip }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: kMode) }
    }
}
