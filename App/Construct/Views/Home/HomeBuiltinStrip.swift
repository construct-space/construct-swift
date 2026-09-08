import SwiftUI
import ConstructCore

/// The fixed top strip on Home — greeting + date + a dynamic feed of
/// announcements / tips / actions. Native port of BuiltinWidgets.vue:
/// CurrentUser (greeting) at left, feed blocks from `{gateway}/api/source/feed`.
struct HomeBuiltinStrip: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.constructTheme) private var theme

    struct FeedBlock: Decodable, Identifiable, Hashable {
        let type: String
        let title: String?
        let body: String?
        let label: String?
        let url: String?
        let route: String?
        let cols: Int?
        var id: String { "\(type):\(title ?? label ?? "")" }
        /// Column span (of 9 feed columns), like the Vue's `block.cols`.
        var span: Int { min(max(cols ?? 3, 1), 9) }
        var kicker: String {
            switch type {
            case "changelog": "Changelog"; case "tip": "Tip"; case "update": "Update"
            case "announcement": "Announcement"; case "action": "Action"; default: type.capitalized
            }
        }
    }

    @State private var blocks: [FeedBlock] = []
    @State private var loaded = false

    // Host strip spec (Image #14): 12 equal columns, 2 rows × 80px, gap-2 (8px).
    private let gap: CGFloat = 8
    private let rowH: CGFloat = 80

    var body: some View {
        GeometryReader { geo in
            let col = max(1, (geo.size.width - gap * 11) / 12)
            HStack(alignment: .top, spacing: gap) {
                greetingCard.frame(width: col * 3 + gap * 2)   // cols 1-3
                dateCard.frame(width: col)                      // col 4
                feedArea(colWidth: col).frame(width: col * 8 + gap * 7) // cols 5-12
            }
        }
        .frame(height: rowH * 2 + gap)
        .padding(.horizontal, 20).padding(.top, 12)
        .task { await loadFeed() }
    }

    // MARK: Greeting (CurrentUser)

    private var greetingCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(timeOfDay).font(.system(size: 15)).foregroundStyle(theme.muted)
            (Text(firstName).foregroundStyle(theme.foreground) + Text(".").foregroundStyle(theme.accent))
                .font(.system(size: 30, weight: .bold))
            Spacer()
            Text("Construct").font(.system(size: 12)).foregroundStyle(theme.muted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(16)
        .background(Rectangle().fill(stripFill))
    }

    private var dateCard: some View {
        VStack(alignment: .leading, spacing: 2) {
            Spacer()
            Text(dayNumber).font(.system(size: 34, weight: .bold)).foregroundStyle(theme.foreground)
            Text(monthDow).font(.system(size: 10, weight: .semibold)).foregroundStyle(theme.muted).tracking(0.5)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        .padding(14)
        .background(Rectangle().fill(stripFill))
    }

    // MARK: Feed

    private static let feedCols = 8  // feed occupies cols 5-12

    /// Greedily pack feed blocks into rows honoring each block's `span` (cols),
    /// clamped to the feed width — the Vue's `gridColumn: span block.cols`.
    private var feedRows: [[FeedBlock]] {
        var rows: [[FeedBlock]] = []
        var row: [FeedBlock] = []
        var used = 0
        for b in blocks.prefix(12) {
            let span = min(b.span, Self.feedCols)
            if used + span > Self.feedCols, !row.isEmpty { rows.append(row); row = []; used = 0 }
            row.append(b); used += span
        }
        if !row.isEmpty { rows.append(row) }
        return rows
    }

    private func feedArea(colWidth: CGFloat) -> some View {
        Group {
            if blocks.isEmpty {
                if loaded {
                    Text("Welcome to Construct").font(.system(size: 11)).foregroundStyle(theme.muted)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ProgressView().controlSize(.small).frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                VStack(spacing: gap) {
                    ForEach(Array(feedRows.enumerated()), id: \.offset) { _, row in
                        HStack(spacing: gap) {
                            ForEach(row) { b in
                                let span = min(b.span, Self.feedCols)
                                feedCard(b).frame(width: colWidth * CGFloat(span) + gap * CGFloat(span - 1))
                            }
                            Spacer(minLength: 0)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func feedCard(_ b: FeedBlock) -> some View {
        Button {
            #if os(macOS)
            if let u = b.url, let url = URL(string: u) { NSWorkspace.shared.open(url) }
            #endif
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                Text(b.kicker.uppercased() + ".").font(.system(size: 9, weight: .semibold)).foregroundStyle(theme.muted).tracking(0.5)
                if let t = b.title { Text(t).font(.system(size: 13, weight: .medium)).foregroundStyle(theme.foreground).lineLimit(1) }
                if let body = b.body { Text(body).font(.system(size: 11)).foregroundStyle(theme.muted).lineLimit(2) }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .frame(height: rowH)
            .padding(12)
            .background(Rectangle().fill(stripFill))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var stripFill: Color { theme.foreground.opacity(0.03) }

    // MARK: Data

    private func loadFeed() async {
        guard !loaded else { return }
        defer { loaded = true }
        guard let token = env.auth.currentAccessToken() else { return }
        var req = URLRequest(url: env.config.gateway.appendingPathComponent("api/source/feed"))
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 8
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return }
        struct Resp: Decodable { let layout: [FeedBlock]?; let items: [FeedBlock]? }
        if let decoded = try? JSONDecoder().decode(Resp.self, from: data) {
            blocks = decoded.layout ?? decoded.items ?? []
        }
    }

    // MARK: Formatting

    private var timeOfDay: String {
        let h = Calendar.current.component(.hour, from: Date())
        switch h { case 5..<12: return "Good morning"; case 12..<18: return "Good afternoon"; case 18..<23: return "Good evening"; default: return "Up late" }
    }
    private var firstName: String {
        env.auth.user?.name?.split(separator: " ").first.map(String.init) ?? env.auth.user?.name ?? "there"
    }
    private var dayNumber: String { let f = DateFormatter(); f.dateFormat = "d"; return f.string(from: Date()) }
    private var monthDow: String { let f = DateFormatter(); f.dateFormat = "EEE · MMM"; return f.string(from: Date()).uppercased() }
}
