import Foundation
import Network

/// A deliberately small HTTP server: one connection, one request line, one
/// response, close. It exists so anything on this machine — a tablet over
/// `adb reverse`, a shell script, an editor plugin, the other app's proxy — can
/// fire an effect without linking against anything.
final class EffectsHttpServer {
    private let router: EffectsRouter
    private var listener: NWListener?
    private let queue = DispatchQueue(label: "victor-effects-http", qos: .utility)
    private(set) var boundPort: UInt16 = 0

    init(router: EffectsRouter) {
        self.router = router
    }

    func start(port: UInt16) {
        let tcpParams = NWParameters.tcp
        tcpParams.allowLocalEndpointReuse = true
        guard let nwPort = NWEndpoint.Port(rawValue: port),
              let listener = try? NWListener(using: tcpParams, on: nwPort) else {
            effectsError("EffectsHttpServer: failed to bind port \(port)")
            return
        }
        boundPort = port
        self.listener = listener
        listener.newConnectionHandler = { [weak self] conn in self?.handle(conn) }
        listener.stateUpdateHandler = { state in
            switch state {
            case .ready: effectsInfo("HTTP server on :\(port)")
            case .failed(let err): effectsError("HTTP server failed: \(err)")
            default: break
            }
        }
        listener.start(queue: queue)
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    private func handle(_ conn: NWConnection) {
        conn.start(queue: queue)
        conn.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, _, _ in
            guard let self else { conn.cancel(); return }
            let raw = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
            let path = EffectsRouter.parsePath(raw)
            let result = self.respond(path: path)
            var out = Self.headers(status: result.status,
                                   contentType: result.contentType,
                                   length: result.body.count)
            out.append(result.body)
            conn.send(content: out, completion: .contentProcessed { _ in conn.cancel() })
        }
    }

    /// Runs one request. **Never call this on the main thread** — it blocks on
    /// `main.sync` because every handler touches AppKit. An in-process caller
    /// that is already on main calls `router.dispatch` instead; that is the
    /// whole reason the two are separate functions.
    func respond(path: String) -> EffectsResponse {
        var result = EffectsResponse.notFound
        DispatchQueue.main.sync {
            result = router.dispatch(path)
        }
        return result
    }

    private static func headers(status: Int, contentType: String, length: Int) -> Data {
        let reason: String
        switch status {
        case 200: reason = "OK"
        case 404: reason = "Not Found"
        case 503: reason = "Service Unavailable"
        default: reason = "OK"
        }
        return Data("HTTP/1.1 \(status) \(reason)\r\nContent-Type: \(contentType)\r\nContent-Length: \(length)\r\n\r\n".utf8)
    }
}
