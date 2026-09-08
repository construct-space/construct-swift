import Foundation
import WebKit

/// Serves a running space's bundle assets over a custom `space://` URL scheme,
/// the native analogue of Tauri's asset protocol. URLs look like
/// `space://<spaceId>/<entry>` and resolve through the space's bundle source.
public final class SpaceSchemeHandler: NSObject, WKURLSchemeHandler {
    public static let scheme = "space"

    /// The synthetic shell entry served for `index.html` (the space-shell HTML).
    public static let shellEntry = "index.html"
    /// The synthetic entry served for the bundled space-shell runtime JS.
    public static let runtimeEntry = "__runtime__.js"
    /// The synthetic entry for the prebuilt Tailwind + UI base stylesheet.
    public static let baseCssEntry = "__base__.css"

    /// Active bundle sources keyed by space id. Populated as spaces load.
    private let sourcesProvider: @Sendable (String) -> SpaceBundleSource?
    /// Provides the space-shell HTML + runtime JS (from app resources). When
    /// nil, only real bundle files are served (raw bundles need their own
    /// index.html).
    private let shellHTML: @Sendable () -> Data?
    private let runtimeJS: @Sendable () -> Data?

    private let baseCSS: @Sendable () -> Data?

    public init(
        sourcesProvider: @escaping @Sendable (String) -> SpaceBundleSource?,
        shellHTML: @escaping @Sendable () -> Data? = { nil },
        runtimeJS: @escaping @Sendable () -> Data? = { nil },
        baseCSS: @escaping @Sendable () -> Data? = { nil }
    ) {
        self.sourcesProvider = sourcesProvider
        self.shellHTML = shellHTML
        self.runtimeJS = runtimeJS
        self.baseCSS = baseCSS
    }

    public func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        guard let url = urlSchemeTask.request.url,
              let host = url.host else {
            urlSchemeTask.didFailWithError(URLError(.badURL))
            return
        }
        let spaceId = host
        // Path without the leading slash is the bundle entry.
        var entry = url.path
        if entry.hasPrefix("/") { entry.removeFirst() }
        if entry.isEmpty { entry = Self.shellEntry }

        // Synthetic entries: the shell HTML and the space-shell runtime, served
        // from app resources so the space and runtime share one origin.
        if entry == Self.shellEntry, let html = shellHTML() {
            respond(urlSchemeTask, url: url, data: html, mime: "text/html; charset=utf-8")
            return
        }
        if entry == Self.runtimeEntry, let js = runtimeJS() {
            respond(urlSchemeTask, url: url, data: js, mime: "text/javascript; charset=utf-8")
            return
        }
        if entry == Self.baseCssEntry, let css = baseCSS() {
            respond(urlSchemeTask, url: url, data: css, mime: "text/css; charset=utf-8")
            return
        }

        guard let source = sourcesProvider(spaceId) else {
            urlSchemeTask.didFailWithError(URLError(.cannotFindHost))
            return
        }

        do {
            let data = try source.readBytes(entry)
            respond(urlSchemeTask, url: url, data: data, mime: Self.mimeType(for: entry))
        } catch {
            urlSchemeTask.didFailWithError(error)
        }
    }

    private func respond(_ task: WKURLSchemeTask, url: URL, data: Data, mime: String) {
        let response = HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: [
                "Content-Type": mime,
                "Access-Control-Allow-Origin": "*",
                "Cache-Control": "no-cache",
            ]
        )!
        task.didReceive(response)
        task.didReceive(data)
        task.didFinish()
    }

    public func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {
        // No streaming state to tear down; reads are synchronous.
    }

    static func mimeType(for entry: String) -> String {
        let ext = (entry as NSString).pathExtension.lowercased()
        switch ext {
        case "html", "htm": return "text/html; charset=utf-8"
        case "js", "mjs": return "text/javascript; charset=utf-8"
        case "css": return "text/css; charset=utf-8"
        case "json": return "application/json; charset=utf-8"
        case "svg": return "image/svg+xml"
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "gif": return "image/gif"
        case "webp": return "image/webp"
        case "woff": return "font/woff"
        case "woff2": return "font/woff2"
        case "ttf": return "font/ttf"
        case "wasm": return "application/wasm"
        default: return "application/octet-stream"
        }
    }
}
