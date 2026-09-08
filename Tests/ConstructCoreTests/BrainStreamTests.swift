import Testing
import Foundation
@testable import ConstructCore

/// Verifies the SSE chunk parser maps the brain's `prompt` wire.Response
/// emit types onto PromptEvent, matching wire_prompt.go's streamHandler.
@Suite("BrainStream")
struct BrainStreamTests {
    private func parse(_ json: String) -> BrainService.PromptEvent? {
        BrainService.parseStreamChunk(Data(json.utf8))
    }

    @Test("text_delta -> .textDelta")
    func textDelta() {
        #expect(parse(#"{"id":"s","type":"text_delta","data":{"delta":"hi"}}"#) == .textDelta("hi"))
    }

    @Test("tool_call -> .toolCall(id, name, input)")
    func toolCall() {
        #expect(parse(#"{"id":"s","type":"tool_call","data":{"id":"t1","name":"read_file","input":{"path":"a"}}}"#)
                == .toolCall(id: "t1", name: "read_file", input: #"{"path":"a"}"#))
    }

    @Test("tool_result carries id, output, is_error")
    func toolResult() {
        #expect(parse(#"{"id":"s","type":"tool_result","data":{"id":"t1","output":"ok","is_error":true}}"#)
                == .toolResult(id: "t1", output: "ok", isError: true))
    }

    @Test("end carries stop_reason")
    func end() {
        #expect(parse(#"{"id":"s","type":"end","success":true,"data":{"stop_reason":"end_turn"},"done":true}"#)
                == .end(stopReason: "end_turn"))
    }

    @Test("top-level error -> .error")
    func error() {
        #expect(parse(#"{"id":"s","success":false,"error":"boom","done":true}"#) == .error("boom"))
    }

    @Test("done without a type is treated as .end")
    func doneWithoutType() {
        #expect(parse(#"{"id":"s","done":true}"#) == .end(stopReason: nil))
    }

    @Test("session chunk is ignored")
    func sessionIgnored() {
        #expect(parse(#"{"id":"s","type":"session","data":{"session_id":"abc"}}"#) == nil)
    }

    @Test("tool_request chunk is ignored")
    func toolRequestIgnored() {
        #expect(parse(#"{"id":"s","type":"tool_request","data":{"id":"t1","name":"x"}}"#) == nil)
    }
}
