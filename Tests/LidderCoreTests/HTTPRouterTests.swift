import Foundation
import Testing
@testable import LidderCore

@Suite struct HTTPRouterTests {

    let demoPage = Data("<h1>demo</h1>".utf8)
    let sample = Sample(angle: 126, velocity: 4.2, ts: 1_780_665_838.404)

    func route(_ requestLine: String, latest: Sample? = nil) -> HTTPRoute {
        let request = Data("\(requestLine)\r\nHost: 127.0.0.1:8765\r\n\r\n".utf8)
        return HTTPRouter.route(request, latest: latest, demoPage: demoPage)
    }

    func body(_ route: HTTPRoute) -> String? {
        guard case .respond(let response) = route else { return nil }
        return String(data: response.body, encoding: .utf8)
    }

    func status(_ route: HTTPRoute) -> String? {
        guard case .respond(let response) = route else { return nil }
        return response.status
    }

    @Test func health() {
        let r = route("GET /health HTTP/1.1")
        #expect(status(r) == "200 OK")
        #expect(body(r) == #"{"ok":true}"#)
    }

    @Test func angleWithSample() {
        let r = route("GET /angle HTTP/1.1", latest: sample)
        #expect(status(r) == "200 OK")
        #expect(body(r) == #"{"angle":126.0,"velocity":4.20,"ts":1780665838.404}"#)
    }

    @Test func angleBeforeFirstSampleIsNull() {
        #expect(body(route("GET /angle HTTP/1.1")) == #"{"angle":null,"velocity":null,"ts":null}"#)
    }

    @Test(arguments: ["/", "/index.html"])
    func demoPageIsServed(path: String) {
        let r = route("GET \(path) HTTP/1.1")
        guard case .respond(let response) = r else {
            Issue.record("expected a response, got \(r)")
            return
        }
        #expect(response.status == "200 OK")
        #expect(response.contentType == "text/html; charset=utf-8")
        #expect(response.body == demoPage)
    }

    @Test func streamKeepsConnectionOpen() {
        #expect(route("GET /stream HTTP/1.1") == .stream)
    }

    @Test func unknownPathIs404() {
        #expect(status(route("GET /nope HTTP/1.1")) == "404 Not Found")
    }

    @Test func nonGetIs405() {
        #expect(status(route("POST /angle HTTP/1.1")) == "405 Method Not Allowed")
    }

    @Test func corsPreflight() {
        #expect(status(route("OPTIONS /stream HTTP/1.1")) == "204 No Content")
    }

    @Test func malformedRequestsAre400() {
        #expect(status(route("GARBAGE")) == "400 Bad Request")
        let notUTF8 = HTTPRouter.route(Data([0xFF, 0xFE, 0xFD]), latest: nil, demoPage: demoPage)
        #expect(status(notUTF8) == "400 Bad Request")
    }

    @Test func serializedResponseHasHeadersAndBody() {
        let response = HTTPResponse(status: "200 OK", contentType: "application/json",
                                    body: Data(#"{"ok":true}"#.utf8))
        let text = String(data: response.serialized, encoding: .utf8)!
        #expect(text.hasPrefix("HTTP/1.1 200 OK\r\n"))
        #expect(text.contains("Content-Type: application/json\r\n"))
        #expect(text.contains("Content-Length: 11\r\n"))
        #expect(text.contains("Access-Control-Allow-Origin: *\r\n"))
        #expect(text.contains("Connection: close\r\n"))
        #expect(text.hasSuffix("\r\n\r\n{\"ok\":true}"))
    }

    @Test func sseHeaderAllowsCrossOriginStreaming() {
        let header = HTTPRouter.sseHeader
        #expect(header.hasPrefix("HTTP/1.1 200 OK\r\n"))
        #expect(header.contains("Content-Type: text/event-stream\r\n"))
        #expect(header.contains("Access-Control-Allow-Origin: *\r\n"))
        #expect(header.hasSuffix("\r\n\r\n"))
    }

    @Test func sseEventFormat() {
        #expect(sample.sseEvent == "data: {\"angle\":126.0,\"velocity\":4.20,\"ts\":1780665838.404}\n\n")
    }
}
