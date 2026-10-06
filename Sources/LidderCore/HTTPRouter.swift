import Foundation

/// A complete HTTP response that closes the connection after sending.
struct HTTPResponse: Equatable {
    let status: String
    var contentType = "text/plain"
    var body = Data()

    /// The full response bytes: status line, headers and body.
    var serialized: Data {
        var header = "HTTP/1.1 \(status)\r\n"
        header += "Content-Type: \(contentType)\r\n"
        header += "Content-Length: \(body.count)\r\n"
        header += "Access-Control-Allow-Origin: *\r\n"
        header += "Access-Control-Allow-Methods: GET, OPTIONS\r\n"
        header += "Connection: close\r\n"
        header += "\r\n"

        var payload = Data(header.utf8)
        payload.append(body)
        return payload
    }
}

/// What the server should do with a request.
enum HTTPRoute: Equatable {
    case respond(HTTPResponse)
    /// Keep the connection open and push Server-Sent Events.
    case stream
}

/// Maps raw request bytes to a route. Pure, so it is testable without sockets.
enum HTTPRouter {

    static let sseHeader = """
    HTTP/1.1 200 OK\r
    Content-Type: text/event-stream\r
    Cache-Control: no-cache\r
    Connection: keep-alive\r
    Access-Control-Allow-Origin: *\r
    \r

    """

    static func route(_ request: Data, latest: Sample?, demoPage: Data) -> HTTPRoute {
        guard let head = String(data: request, encoding: .utf8) else {
            return .respond(HTTPResponse(status: "400 Bad Request"))
        }
        // Request line: "<METHOD> <PATH> HTTP/1.1"
        let firstLine = head.split(separator: "\r\n", maxSplits: 1).first ?? ""
        let parts = firstLine.split(separator: " ")
        guard parts.count >= 2 else {
            return .respond(HTTPResponse(status: "400 Bad Request"))
        }
        let method = String(parts[0])
        let path = String(parts[1])

        if method == "OPTIONS" {
            return .respond(HTTPResponse(status: "204 No Content"))
        }
        guard method == "GET" else {
            return .respond(HTTPResponse(status: "405 Method Not Allowed"))
        }

        switch path {
        case "/stream":
            return .stream
        case "/angle":
            let body = latest?.json ?? "{\"angle\":null,\"velocity\":null,\"ts\":null}"
            return .respond(HTTPResponse(status: "200 OK", contentType: "application/json",
                                         body: Data(body.utf8)))
        case "/health":
            return .respond(HTTPResponse(status: "200 OK", contentType: "application/json",
                                         body: Data("{\"ok\":true}".utf8)))
        case "/", "/index.html":
            return .respond(HTTPResponse(status: "200 OK", contentType: "text/html; charset=utf-8",
                                         body: demoPage))
        default:
            return .respond(HTTPResponse(status: "404 Not Found",
                                         body: Data("not found\n".utf8)))
        }
    }
}
