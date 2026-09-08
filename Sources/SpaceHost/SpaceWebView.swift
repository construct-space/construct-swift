import Foundation
import WebKit
import SwiftUI

/// Builds and configures the WKWebView that hosts a space, including the
/// `space://` scheme handler, the bridge message handler, and the JS bootstrap
/// that defines `window.construct`.
@MainActor
public enum SpaceWebViewFactory {
    /// Creates a configured webview for a space.
    /// - Parameters:
    ///   - context: host services exposed to the space.
    ///   - schemeHandler: serves `space://` bundle assets.
    ///   - hostRuntimeJS: optional shared-libs bundle that populates
    ///     `window.__CONSTRUCT__` (Vue/Pinia/etc). Spaces externalize these,
    ///     so this must be shipped as an app resource for real spaces to run.
    public static func makeWebView(
        context: SpaceHostContext,
        schemeHandler: SpaceSchemeHandler,
        hostRuntimeJS: String? = nil,
        widgetsBootJSON: String? = nil,
        themeScript: String? = nil,
        homeEditHandler: (@MainActor (String) -> Void)? = nil
    ) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.setURLSchemeHandler(schemeHandler, forURLScheme: SpaceSchemeHandler.scheme)

        let controller = WKUserContentController()

        // 0. Live host theme → :root --app-* vars (before any content paints), so
        //    widgets/spaces match the app theme instead of base.css's default.
        if let themeScript {
            controller.addUserScript(WKUserScript(
                source: themeScript, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        }

        // 1. Shared libs bundle (window.__CONSTRUCT__), if provided.
        if let hostRuntimeJS {
            controller.addUserScript(WKUserScript(
                source: hostRuntimeJS,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: true
            ))
        }

        // 2. The window.construct runtime shim.
        controller.addUserScript(WKUserScript(
            source: bootstrapJS(context: context),
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        ))

        // 2b. The boot descriptor the space-shell HTML reads to mount.
        let boot = """
        window.__SPACE_BOOT__ = { id: \(jsString(context.spaceId)), initialPath: \(jsString(context.initialPath ?? "")) };
        """
        controller.addUserScript(WKUserScript(
            source: boot,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        ))

        // 2c. Widget-dashboard boot (Home), when provided.
        if let widgetsBootJSON {
            controller.addUserScript(WKUserScript(
                source: "window.__WIDGETS_BOOT__ = \(widgetsBootJSON);",
                injectionTime: .atDocumentStart,
                forMainFrameOnly: true
            ))
        }

        // 3. The space → host bridge.
        let bridge = SpaceBridge(context: context)
        controller.addScriptMessageHandler(bridge, contentWorld: .page, name: SpaceBridge.handlerName)

        // 3a. Home-edit channel (widget grid → native: remove/resize/add).
        if let homeEditHandler {
            controller.add(HomeEditBridge(handler: homeEditHandler), name: "homeEdit")
        }

        // 3b. Console/error capture → native log (debug aid for blank screens).
        let logger = SpaceConsoleLogger(spaceId: context.spaceId)
        controller.add(logger, name: SpaceConsoleLogger.handlerName)
        controller.addUserScript(WKUserScript(
            source: consoleCaptureJS,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        ))

        config.userContentController = controller
        config.defaultWebpagePreferences.allowsContentJavaScript = true

        let webView = WKWebView(frame: .zero, configuration: config)
        #if DEBUG
        // Allow Safari Web Inspector attachment in debug builds.
        webView.isInspectable = true
        #endif
        return webView
    }
}

/// Receives home-edit actions (remove/resize/add) from the widget grid webview
/// and forwards the raw JSON to the native handler.
private final class HomeEditBridge: NSObject, WKScriptMessageHandler {
    private let handler: @MainActor (String) -> Void
    init(handler: @escaping @MainActor (String) -> Void) { self.handler = handler }
    func userContentController(_ uc: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? String else { return }
        MainActor.assumeIsolated { handler(body) }
    }
}

extension SpaceWebViewFactory {

    /// The JS that defines `window.construct`, bridging to native via the
    /// reply-capable message handler (postMessage returns a Promise).
    static func bootstrapJS(context: SpaceHostContext) -> String {
        // Encode the static parts safely.
        let cfg = """
        {"graphUrl":\(jsString(context.config.graphURL)),"apiBase":\(jsString(context.config.apiBase))}
        """
        let spaceId = jsString(context.spaceId)
        let projectId = context.projectId.map(jsString) ?? "null"
        let scope = jsString(context.scope)

        return """
        (function () {
          function call(method, params) {
            return window.webkit.messageHandlers.\(SpaceBridge.handlerName)
              .postMessage({ method: method, params: params || {} });
          }
          window.construct = {
            config: \(cfg),
            space: { id: \(spaceId) },
            project: { id: \(projectId) },
            scope: \(scope),
            auth: {
              getAccessToken: function () { return call('auth.getAccessToken'); },
              getUserId: function () { return call('auth.getUserId'); }
            },
            storage: {
              get: function (key) { return call('storage.get', { key: key }); },
              set: function (key, value) { return call('storage.set', { key: key, value: value }); },
              remove: function (key) { return call('storage.remove', { key: key }); }
            },
            graph: {
              query: function (query, variables, options) {
                var sid = (options && options.spaceId) || (window.construct.space && window.construct.space.id);
                return call('graph.query', { query: query, variables: variables || {}, spaceId: sid });
              }
            },
            operator: {
              send: function (type, payload) { return call('operator.send', { type: type, payload: payload || {} }); }
            },
            shell: {
              openUrl: function (url) { return call('shell.openUrl', { url: url }); }
            },
            context: {
              publish: function (type, summary) { return call('context.publish', { type: type, summary: summary || {} }); }
            }
          };
        })();
        """
    }

    /// Forwards console.* and window errors to the native logger.
    static let consoleCaptureJS = """
    (function () {
      function send(level, args) {
        try {
          window.webkit.messageHandlers.\(SpaceConsoleLogger.handlerName).postMessage({
            level: level,
            text: Array.prototype.map.call(args, function (a) {
              try {
                if (a instanceof Error) return (a.message || a.name) + (a.stack ? ('\\n' + a.stack) : '');
                if (typeof a === 'string') return a;
                var s = JSON.stringify(a);
                return (s === '{}' && a && a.toString) ? a.toString() : s;
              } catch (e) { return String(a); }
            }).join(' ')
          });
        } catch (e) {}
      }
      ['log', 'info', 'warn', 'error', 'debug'].forEach(function (lvl) {
        var orig = console[lvl];
        console[lvl] = function () { send(lvl, arguments); if (orig) orig.apply(console, arguments); };
      });
      window.addEventListener('error', function (e) {
        send('error', [(e.message || 'error') + ' @ ' + (e.filename || '') + ':' + (e.lineno || '')]);
      });
      window.addEventListener('unhandledrejection', function (e) {
        send('error', ['unhandledrejection: ' + (e.reason && e.reason.stack || e.reason)]);
      });
    })();
    """

    /// JSON-encodes a string for safe embedding in generated JS.
    static func jsString(_ s: String) -> String {
        let data = try? JSONSerialization.data(withJSONObject: [s])
        if let data, let arr = String(data: data, encoding: .utf8) {
            // arr is `["..."]`; strip the brackets.
            return String(arr.dropFirst().dropLast())
        }
        return "\"\""
    }
}

#if os(macOS)
import AppKit

/// SwiftUI wrapper hosting a space webview on macOS.
public struct SpaceWebView: NSViewRepresentable {
    let webView: WKWebView
    let initialURL: URL

    public init(webView: WKWebView, initialURL: URL) {
        self.webView = webView
        self.initialURL = initialURL
    }

    public func makeNSView(context: Context) -> WKWebView {
        webView.load(URLRequest(url: initialURL))
        return webView
    }

    public func updateNSView(_ nsView: WKWebView, context: Context) {}
}
#elseif os(iOS)
import UIKit

/// SwiftUI wrapper hosting a space webview on iOS.
public struct SpaceWebView: UIViewRepresentable {
    let webView: WKWebView
    let initialURL: URL

    public init(webView: WKWebView, initialURL: URL) {
        self.webView = webView
        self.initialURL = initialURL
    }

    public func makeUIView(context: Context) -> WKWebView {
        webView.load(URLRequest(url: initialURL))
        return webView
    }

    public func updateUIView(_ uiView: WKWebView, context: Context) {}
}
#endif
