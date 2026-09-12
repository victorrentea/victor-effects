import Foundation

/// One tile, two clips, taken in turns.
///
/// The grid is finite — 13 columns of artwork Victor can hit without reading —
/// so a second take of a joke that is already on the board does not deserve its
/// own square. #19 *fail* and #20 *fail2* were exactly that: the same trombone
/// beat twice, two tiles wide, and the room only ever heard whichever one his
/// thumb happened to land on. They are now ONE button: press #19 and the runs
/// alternate 19 → 20 → 19 → …, so the second press of the evening is not the
/// same noise as the first.
///
/// Three properties are deliberate:
///
///  - **The cursor is in memory only.** A restart of the app begins the pair
///    again at its first file. Nothing on disk is worth the alternation being
///    one file "off" after a crash mid-workshop, and the point is variety
///    within a session, not a ledger across them.
///  - **The table is keyed by the asset the CLIENT presses**, and its first
///    entry is normally that same asset — the tablet, the panel and every
///    script keep sending `/sound/play/19_fail.mp3` and know nothing about
///    this. The partner tile keeps its asset and its artwork (the grid is
///    numbered `#NN` by position; removing a row would renumber sixty tiles),
///    it only stops being a separate press — hence the `N/A` label it now
///    carries in `tiles.json`.
///  - **An asset that is not in the table is returned untouched**, so the
///    lookup can sit unconditionally at the top of `EffectsEngine.playSound`.
///
/// Adding the next pair is one line in [defaultTable]. Only the KEY is pressed;
/// pressing a partner asset directly is left alone (it plays itself, as it
/// always did) — one entry point per pair keeps "what does this press do"
/// answerable by reading one row.
final class AlternatingSounds {

    /// The pairs (or longer cycles — nothing here assumes two) in play.
    static let defaultTable: [String: [String]] = [
        // 💥 #19 fail / #20 fail2 — the same trombone, two takes.
        "19_fail.mp3": ["19_fail.mp3", "20_fail2.mp3"],
    ]

    /// The app's cursor. Main-thread only, like everything `dispatch` reaches.
    static let shared = AlternatingSounds()

    private let table: [String: [String]]

    /// Where each cycle is up to. Index of the file the NEXT press will play.
    private var cursor: [String: Int] = [:]

    init(table: [String: [String]] = AlternatingSounds.defaultTable) {
        self.table = table
    }

    /// The file to play for this press of `asset`, advancing its cycle.
    /// Unknown assets — every tile but the ones listed above — come back as
    /// they went in.
    func next(for asset: String) -> String {
        guard let files = table[asset], !files.isEmpty else { return asset }
        let index = (cursor[asset] ?? 0) % files.count
        cursor[asset] = (index + 1) % files.count
        return files[index]
    }

    /// What the next press would play, without spending it. For tests and for
    /// anything that wants to describe the state rather than change it.
    func peek(for asset: String) -> String {
        guard let files = table[asset], !files.isEmpty else { return asset }
        return files[(cursor[asset] ?? 0) % files.count]
    }

    /// Back to the top of every cycle.
    func reset() { cursor.removeAll() }
}
