import Foundation

/// The one thing this app pushes instead of answering: a fire-and-forget GET to
/// `eventWebhook` when a gesture that started here has to finish somewhere else.
///
/// Today that is exactly one event — a ☕ charged up under the cursor and
/// popped, which in Victor's setup pulls the break timer (owned by the other
/// app) closer. It is a webhook and not a shared library because the payoff
/// needs state this process does not have, and a GET with two numbers is the
/// smallest thing that can carry the gesture across.
///
/// Fire-and-forget by design: nothing here waits on, retries, or reports a
/// failed delivery. A missed pop is a missed minute, never a stuck effect.
enum EventWebhook {
    private static let session: URLSession = {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 1.0
        cfg.waitsForConnectivity = false
        return URLSession(configuration: cfg)
    }()

    static func fire(type: String, params: [String: String] = [:]) {
        let base = EffectsConfig.shared.eventWebhook
        guard !base.isEmpty, var comps = URLComponents(string: base) else { return }
        var items = comps.queryItems ?? []
        items.append(URLQueryItem(name: "type", value: type))
        for key in params.keys.sorted() {
            items.append(URLQueryItem(name: key, value: params[key]))
        }
        comps.queryItems = items
        guard let url = comps.url else { return }
        session.dataTask(with: url) { _, _, err in
            if let err {
                effectsInfo("webhook \(type) not delivered: \(err.localizedDescription)")
            }
        }.resume()
    }

    static func coffeePopped(at point: CGPoint) {
        fire(type: "coffee-popped",
             params: ["x": String(Int(point.x.rounded())),
                      "y": String(Int(point.y.rounded()))])
    }
}
