import Testing
import Foundation
@testable import SpaceHost

@Suite("Space operator policy")
struct SpaceOperatorPolicyTests {
    @Test("Allows media.* and storage.* prefixes")
    func allowed() {
        #expect(SpaceOperatorPolicy.isAllowed("media.transcribe"))
        #expect(SpaceOperatorPolicy.isAllowed("storage.upload"))
    }

    @Test("Rejects arbitrary operator methods")
    func rejected() {
        #expect(!SpaceOperatorPolicy.isAllowed("shell.exec"))
        #expect(!SpaceOperatorPolicy.isAllowed("fs.read"))
        #expect(!SpaceOperatorPolicy.isAllowed(""))
    }
}

@Suite("Scheme handler MIME types")
struct SchemeHandlerTests {
    @Test("Maps common extensions")
    func mimeTypes() {
        #expect(SpaceSchemeHandler.mimeType(for: "app.js").hasPrefix("text/javascript"))
        #expect(SpaceSchemeHandler.mimeType(for: "index.html").hasPrefix("text/html"))
        #expect(SpaceSchemeHandler.mimeType(for: "style.css").hasPrefix("text/css"))
        #expect(SpaceSchemeHandler.mimeType(for: "logo.svg") == "image/svg+xml")
        #expect(SpaceSchemeHandler.mimeType(for: "data.bin") == "application/octet-stream")
    }
}

@Suite("AnyCodableValue")
struct AnyCodableValueTests {
    @Test("Builds from Foundation JSON objects")
    func fromAny() {
        let value = AnyCodableValue.from(["a": 1, "b": "x", "c": true])
        guard case let .object(obj) = value else { Issue.record("not object"); return }
        #expect(obj["b"] == .string("x"))
        #expect(obj["c"] == .bool(true))
        if case let .number(n) = obj["a"] { #expect(n == 1) } else { Issue.record("a not number") }
    }

    @Test("Round-trips through JSON encode/decode")
    func roundTrip() throws {
        let value = AnyCodableValue.object([
            "list": .array([.number(1), .string("two"), .null]),
            "flag": .bool(false),
        ])
        let data = try JSONEncoder().encode(value)
        let decoded = try JSONDecoder().decode(AnyCodableValue.self, from: data)
        #expect(decoded == value)
    }
}
