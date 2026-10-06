import Foundation
import Network

/// Minimal localhost HTTP/1.1 + SSE server exposing the lid angle stream.
///
/// Bound to 127.0.0.1 only — the sensor feed is never exposed to the LAN, and
/// macOS shows no incoming-connection firewall prompt.
final class HTTPServer {

    private let poller: SensorPoller
    private let port: NWEndpoint.Port
    private let queue = DispatchQueue(label: "lidder.http")
    private var listener: NWListener?
    private let demoPage: Data

    init(poller: SensorPoller, port: UInt16) {
        self.poller = poller
        self.port = NWEndpoint.Port(rawValue: port)!
        self.demoPage = HTTPServer.loadDemoPage()
    }

    func start() throws {
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
        guard let head = String(data: request, encoding: .utf8) else {
            send(conn, status: "400 Bad Request", body: Data(), close: true)
            return
        }
        // Request line: "<METHOD> <PATH> HTTP/1.1"
        let firstLine = head.split(separator: "\r\n", maxSplits: 1).first ?? ""
        let parts = firstLine.split(separator: " ")
        guard parts.count >= 2 else {
            send(conn, status: "400 Bad Request", body: Data(), close: true)
            return
        }
        let method = String(parts[0])
        let path = String(parts[1])

        if method == "OPTIONS" {
            send(conn, status: "204 No Content", body: Data(), close: true)
            return
        }
        guard method == "GET" else {
            send(conn, status: "405 Method Not Allowed", body: Data(), close: true)
            return
        }

        switch path {
        case "/stream":
            startSSE(conn)
        case "/angle":
            let body = (poller.latest?.json ?? "{\"angle\":null,\"velocity\":null,\"ts\":null}")
            send(conn, status: "200 OK", contentType: "application/json",
                 body: Data(body.utf8), close: true)
        case "/health":
            send(conn, status: "200 OK", contentType: "application/json",
                 body: Data("{\"ok\":true}".utf8), close: true)
        case "/", "/index.html":
            send(conn, status: "200 OK", contentType: "text/html; charset=utf-8",
                 body: demoPage, close: true)
        default:
            send(conn, status: "404 Not Found", contentType: "text/plain",
                 body: Data("not found\n".utf8), close: true)
        }
    }

    // MARK: Server-Sent Events

    private func startSSE(_ conn: NWConnection) {
        let header = """
        HTTP/1.1 200 OK\r
        Content-Type: text/event-stream\r
        Cache-Control: no-cache\r
        Connection: keep-alive\r
        Access-Control-Allow-Origin: *\r
        \r

        """
        conn.send(content: Data(header.utf8), completion: .contentProcessed { _ in })

        // Push the latest sample immediately so the client isn't blank until
        // the next tick.
        if let latest = poller.latest {
            conn.send(content: Data("data: \(latest.json)\n\n".utf8),
                      completion: .contentProcessed { _ in })
        }

        let token = poller.addSubscriber { [weak conn] sample in
            guard let conn else { return }
            conn.send(content: Data("data: \(sample.json)\n\n".utf8),
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

    // MARK: Response helper

    private func send(_ conn: NWConnection, status: String,
                      contentType: String = "text/plain",
                      body: Data, close: Bool) {
        var header = "HTTP/1.1 \(status)\r\n"
        header += "Content-Type: \(contentType)\r\n"
        header += "Content-Length: \(body.count)\r\n"
        header += "Access-Control-Allow-Origin: *\r\n"
        header += "Access-Control-Allow-Methods: GET, OPTIONS\r\n"
        header += "Connection: close\r\n"
        header += "\r\n"

        var payload = Data(header.utf8)
        payload.append(body)
        conn.send(content: payload, completion: .contentProcessed { _ in
            if close { conn.cancel() }
        })
    }

    // MARK: Demo page loading

    private static func loadDemoPage() -> Data {
        if let url = Bundle.module.url(forResource: "index", withExtension: "html"),
           let data = try? Data(contentsOf: url) {
            return data
        }
        return Data("<!doctype html><h1>lidder</h1><p>Demo page not found.</p>".utf8)
    }
}

func log(_ message: String) {
    FileHandle.standardError.write(Data("[lidder] \(message)\n".utf8))
}
