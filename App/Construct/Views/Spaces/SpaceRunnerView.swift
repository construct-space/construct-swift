import SwiftUI
import WebKit
import ConstructCore
import SpaceHost

/// Hosts a running space in a WKWebView via the SpaceHost bridge. Port of
/// SpaceRunnerPage.vue / DynamicSpacePage.vue — spaces stay as WebUI.
struct SpaceRunnerView: View {
    @Environment(AppEnvironment.self) private var env
    let spaceId: String
    var pageIndex: Int = 0

    var body: some View {
        Group {
            // Native core spaces render in SwiftUI (no webview); store spaces
            // fall through to the WebUI runner.
            if let native = NativeSpaceRegistry.space(for: spaceId) {
                native.make()
            } else if let space = env.spaces.installed.first(where: { $0.id == spaceId }) {
                SpaceContainer(space: space, env: env, initialPath: pagePath(space))
                    .id("\(space.id)#\(pageIndex)")
            } else {
                ContentUnavailableView(
                    "Space not found",
                    systemImage: "exclamationmark.triangle",
                    description: Text("The space \(spaceId) is not installed.")
                )
            }
        }
    }

    /// The in-space route path for the active page index.
    private func pagePath(_ space: InstalledSpace) -> String {
        guard pageIndex >= 0, pageIndex < space.manifest.pages.count else { return "" }
        return space.manifest.pages[pageIndex].path
    }
}

/// Builds the host context + webview for one space. Separated so the webview is
/// constructed once per space id.
private struct SpaceContainer: View {
    let space: InstalledSpace
    let env: AppEnvironment
    var initialPath: String = ""
    @Environment(\.constructTheme) private var theme

    @State private var webView: WKWebView?

    var body: some View {
        ZStack {
            if let webView {
                SpaceWebView(
                    webView: webView,
                    initialURL: URL(string: "\(SpaceSchemeHandler.scheme)://\(space.id)/index.html")!
                )
            } else {
                ProgressView()
            }
        }
        .onAppear { build() }
    }

    @MainActor
    private func build() {
        guard webView == nil else { return }

        // Directory bundles (dev-linked) and packed .space ZIPs (Tauri/CLI).
        let source: any SpaceBundleSource = space.isUnpacked
            ? DirectorySpaceSource(spaceId: space.id, root: space.bundleURL)
            : ZipSpaceSource(spaceId: space.id, archive: space.bundleURL)

        // Serve the space-shell HTML + runtime from app resources so the space
        // and runtime share the space:// origin.
        let schemeHandler = SpaceSchemeHandler(
            sourcesProvider: { id in id == space.id ? source : nil },
            shellHTML: { SpaceShellResources.shellHTML },
            runtimeJS: { SpaceShellResources.runtimeJS },
            baseCSS: { SpaceShellResources.baseCSS }
        )

        let context = makeContext(for: space)
        webView = SpaceWebViewFactory.makeWebView(
            context: context,
            schemeHandler: schemeHandler,
            hostRuntimeJS: nil, // runtime is loaded via __runtime__.js, not injected
            themeScript: theme.cssThemeScript()
        )
    }

    /// Wires the SpaceHostContext to the live app environment.
    @MainActor
    private func makeContext(for space: InstalledSpace) -> SpaceHostContext {
        let auth = env.auth
        let config = env.config
        let storeKeyPrefix = "space:\(space.id):"
        // Snapshot of the user id (stable per session; the sync closure can't
        // hop to the main actor).
        let userId = auth.user?.id

        return SpaceHostContext(
            config: .init(graphURL: config.graph.absoluteString,
                          apiBase: config.gateway.absoluteString),
            spaceId: space.id,
            scope: auth.scope.scope.rawValue,
            initialPath: initialPath,
            accessToken: { await MainActor.run { auth.currentAccessToken() } },
            userId: { userId },
            storageGet: { key in UserDefaults.standard.string(forKey: storeKeyPrefix + key) },
            storageSet: { key, value in UserDefaults.standard.set(value, forKey: storeKeyPrefix + key) },
            storageRemove: { key in UserDefaults.standard.removeObject(forKey: storeKeyPrefix + key) },
            graphQuery: { query, variables, reqSpaceId in
                // Host-mediated GraphQL bridge: POST {graphUrl}/graphql with the
                // bearer token + tenant headers, matching construct-app.
                let token = await MainActor.run { auth.currentAccessToken() }
                var req = URLRequest(url: config.graph.appendingPathComponent("graphql"))
                req.httpMethod = "POST"
                req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                req.setValue(reqSpaceId ?? space.id, forHTTPHeaderField: "X-Space-ID")
                req.setValue("default", forHTTPHeaderField: "X-Project-ID")
                if let token { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
                let varsObj = variables.mapValues { $0.foundationValue }
                req.httpBody = try JSONSerialization.data(withJSONObject: ["query": query, "variables": varsObj])

                let (data, resp) = try await URLSession.shared.data(for: req)
                if let http = resp as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                    let body = String(data: data, encoding: .utf8) ?? ""
                    throw SpaceBridgeError.unknownMethod("graph HTTP \(http.statusCode): \(body.prefix(200))")
                }
                let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                if let errors = obj?["errors"] as? [[String: Any]], !errors.isEmpty {
                    let msgs = errors.compactMap { $0["message"] as? String }.joined(separator: "; ")
                    throw SpaceBridgeError.unknownMethod("graph errors: \(msgs)")
                }
                return AnyCodableValue.from(obj?["data"] ?? NSNull())
            },
            operatorSend: { method, _ in
                throw SpaceBridgeError.unknownMethod("operator.send:\(method) (not yet wired)")
            },
            openURL: { urlString in
                #if os(macOS)
                if let url = URL(string: urlString) { NSWorkspace.shared.open(url) }
                #endif
            }
        )
    }
}

/// Loads the bundled space-shell resources (the WebUI runtime + HTML shell)
/// that render space bundles. Built from `space-shell/` and copied into
/// `Resources/spaceshell/`.
enum SpaceShellResources {
    static let shellHTML: Data? = load("space-shell", "html")
    static let homeHTML: Data? = load("home", "html")
    static let runtimeJS: Data? = load("space-shell", "js")
    /// Prebuilt Tailwind v4 + @construct-space/ui base stylesheet.
    static let baseCSS: Data? = load("base", "css")

    private static func load(_ name: String, _ ext: String) -> Data? {
        // Resources land in a `spaceshell` subdirectory of the app bundle.
        if let url = Bundle.main.url(forResource: name, withExtension: ext, subdirectory: "spaceshell")
            ?? Bundle.main.url(forResource: name, withExtension: ext) {
            return try? Data(contentsOf: url)
        }
        return nil
    }
}
