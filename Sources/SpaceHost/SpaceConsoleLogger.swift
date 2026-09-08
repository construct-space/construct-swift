import Foundation
import os
import WebKit

/// Captures a space webview's console output and JS errors. A debugging aid
/// (especially for blank-screen mounts). Logs to the unified log and, in DEBUG,
/// appends to `/tmp/construct-space-console.log` with an immediate flush so the
/// output is readable even though a GUI app's stdout is block-buffered.
public final class SpaceConsoleLogger: NSObject, WKScriptMessageHandler {
    public static let handlerName = "constructLog"
    private let spaceId: String
    private let logger = Logger(subsystem: "space.construct.app", category: "space-console")

    public init(spaceId: String) {
        self.spaceId = spaceId
    }

    public func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard let body = message.body as? [String: Any] else { return }
        let level = body["level"] as? String ?? "log"
        let text = body["text"] as? String ?? ""
        let line = "[space:\(spaceId)] [\(level)] \(text)"
        logger.log("\(line, privacy: .public)")
        #if DEBUG
        Self.appendToFile(line)
        #endif
    }

    #if DEBUG
    private static let logURL = URL(fileURLWithPath: "/tmp/construct-space-console.log")
    private static func appendToFile(_ line: String) {
        let data = Data((line + "\n").utf8)
        if let handle = try? FileHandle(forWritingTo: logURL) {
            handle.seekToEndOfFile()
            handle.write(data)
            try? handle.close()
        } else {
            try? data.write(to: logURL)
        }
    }
    #endif
}
