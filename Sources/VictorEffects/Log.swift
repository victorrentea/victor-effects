import Foundation

// Shared log formatter:
//   HH:MM:SS.f  PID  [name      ] info    message
//   HH:MM:SS.f  PID  [name      ] error   message
//
// Example:
//   18:49:42.1 66445  [fx        ] info    HTTP server listening on 55124

private let _pid = Int(ProcessInfo.processInfo.processIdentifier)
// name padded to 10 so the message column is always aligned
private let _name = "fx        "

func effectsInfo(_ msg: String) { _effectsLog("info", msg) }
func effectsError(_ msg: String) { _effectsLog("error", msg) }

private func _effectsLog(_ level: String, _ msg: String) {
    let now = Date()
    let c = Calendar.current
    let h = c.component(.hour, from: now)
    let m = c.component(.minute, from: now)
    let s = c.component(.second, from: now)
    let f = c.component(.nanosecond, from: now) / 100_000_000
    let ts = String(format: "%02d:%02d:%02d.%d", h, m, s, f)
    // "info    " and "error   " both = 8 display cols
    let lvl = level == "error" ? "error   " : "info    "
    let line = "\(ts) \(String(format: "%5d", _pid))  [\(_name)] \(lvl)\(msg)"
    if level == "error" {
        FileHandle.standardError.write((line + "\n").data(using: .utf8)!)
    } else {
        print(line)
    }
}

/// The moved code came from an app whose log functions were called
/// `overlayInfo`/`overlayError`. Keeping the names as thin aliases means the
/// ~9k lines of animator code moved verbatim, with no mechanical rename that
/// would have buried the real edits in the diff.
func overlayInfo(_ msg: String) { effectsInfo(msg) }
func overlayError(_ msg: String) { effectsError(msg) }
