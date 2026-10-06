import Foundation
import Network

/// Minimal localhost HTTP/1.1 + SSE server exposing the lid angle stream.
///
/// Bound to 127.0.0.1 only — the sensor feed is never exposed to the LAN, and
/// macOS shows no incoming-connection firewall prompt.
public final class HTTPServer {

    private let poller: SensorPoller
    private let port: NWEndpoint.Port
    private let queue = DispatchQueue(label: "lidder.http")
    private var listener: NWListener?
    private let demoPage: Data

    public init(poller: SensorPoller, port: UInt16) {
        self.poller = poller
        self.port = NWEndpoint.Port(rawValue: port)!
        self.demoPage = Data(demoPageHTML.utf8)
    }

    public func start() throws {
        let params = NWParameters.tcp
        params.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: port)
        params.allowLocalEndpointReuse = true

        let listener = try NWListener(using: params)
        listener.newConnectionHandler = { [weak self] conn in
            self?.accept(conn)
        }
        listener.start(queue: queue)
        self.listener = listener
    }

    // MARK: Connection handling

    private func accept(_ conn: NWConnection) {
        conn.start(queue: queue)
        conn.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let data, !data.isEmpty {
                self.route(conn, request: data)
            } else if isComplete || error != nil {
                conn.cancel()
            }
        }
    }

    private func route(_ conn: NWConnection, request: Data) {
        switch HTTPRouter.route(request, latest: poller.latest, demoPage: demoPage) {
        case .stream:
            startSSE(conn)
        case .respond(let response):
            conn.send(content: response.serialized, completion: .contentProcessed { _ in
                conn.cancel()
            })
        }
    }

    // MARK: Server-Sent Events

    private func startSSE(_ conn: NWConnection) {
        conn.send(content: Data(HTTPRouter.sseHeader.utf8), completion: .contentProcessed { _ in })

        // Push the latest sample immediately so the client isn't blank until
        // the next tick.
        if let latest = poller.latest {
            conn.send(content: Data(latest.sseEvent.utf8),
                      completion: .contentProcessed { _ in })
        }

        let token = poller.addSubscriber { [weak conn] sample in
            guard let conn else { return }
            conn.send(content: Data(sample.sseEvent.utf8),
                      completion: .contentProcessed { _ in })
        }

        conn.stateUpdateHandler = { [weak self] state in
            switch state {
            case .cancelled, .failed:
                self?.poller.removeSubscriber(token)
            default:
                break
            }
        }
        log("client connected to /stream")
    }
}

func log(_ message: String) {
    FileHandle.standardError.write(Data("[lidder] \(message)\n".utf8))
}
