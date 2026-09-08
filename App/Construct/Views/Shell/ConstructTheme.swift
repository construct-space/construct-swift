import SwiftUI

/// Construct design tokens, ported from the host's CSS variables (`--app-*`).
/// Drives the native chrome so the Swift app matches the Tauri app.
struct ConstructTheme: Sendable, Equatable {
    var id: String
    var name: String
    var isDark: Bool
    var background: Color
    var foreground: Color
    var muted: Color
    var accent: Color
    var accentForeground: Color
    var border: Color
    var surface: Color
    var inputBg: Color
    var cardBg: Color
    var cardHover: Color
    var canvasBg: Color

    /// Builds a full theme from the four base colors the host defines per theme,
    /// deriving border/surface/input/canvas consistently.
    static func make(id: String, name: String, isDark: Bool,
                     bg: UInt32, fg: UInt32, muted: UInt32, accent: UInt32) -> ConstructTheme {
        // Surfaces are *derived* from the base color with the host's exact
        // algorithm (applyThemeColors: darken/lighten the background), so we
        // never hardcode per-theme surface palettes and colors match 1:1.
        let canvas  = isDark ? Color.darken(bg, 0.30) : Color.darken(bg, 0.05)
        let border  = isDark ? Color.lighten(bg, 0.15) : Color.darken(bg, 0.10)
        let surface = isDark ? Color.lighten(bg, 0.08) : Color.darken(bg, 0.02)
        let input   = isDark ? Color.lighten(bg, 0.05) : Color.darken(bg, 0.04)
        return ConstructTheme(
            id: id, name: name, isDark: isDark,
            background: Color.hex(bg),
            foreground: Color.hex(fg),
            muted: Color.hex(muted),
            accent: Color.hex(accent),
            accentForeground: .white,
            border: border,
            surface: surface,
            inputBg: input,
            cardBg: surface,
            cardHover: input,
            canvasBg: canvas
        )
    }

    static let light = ConstructThemes.byId("vs")
    static let dark = ConstructThemes.byId("vs-dark")

    /// JS that writes the live theme onto a webview's `:root` as the `--app-*`
    /// CSS variables space widgets read — so widgets match the host theme
    /// instead of base.css's static default. Injected at document start.
    func cssThemeScript() -> String {
        let vars: [(String, Color)] = [
            ("--app-background", background), ("--app-foreground", foreground),
            ("--app-muted", muted), ("--app-accent", accent),
            ("--app-accent-foreground", accentForeground), ("--app-border", border),
            ("--app-surface", surface), ("--app-card-bg", cardBg), ("--app-card-hover", cardHover),
            ("--app-input-bg", inputBg), ("--app-canvas-bg", canvasBg),
        ]
        let sets = vars.map { "r.setProperty('\($0.0)','\($0.1.cssHex)');" }.joined()
        return "(function(){var r=document.documentElement.style;\(sets)"
            + "document.documentElement.style.colorScheme='\(isDark ? "dark" : "light")';})();"
    }
}

extension Color {
    /// "#RRGGBB" in sRGB — for handing SwiftUI colors to web content.
    var cssHex: String {
        #if os(macOS)
        let ns = NSColor(self).usingColorSpace(.sRGB) ?? .black
        let r = Int((ns.redComponent * 255).rounded())
        let g = Int((ns.greenComponent * 255).rounded())
        let b = Int((ns.blueComponent * 255).rounded())
        return String(format: "#%02X%02X%02X", r, g, b)
        #else
        return "#000000"
        #endif
    }
}

/// The selectable theme catalog, mirroring the host's useAppTheme themes.
enum ConstructThemes {
    static let all: [ConstructTheme] = [
        .make(id: "vs", name: "Light", isDark: false, bg: 0xF1F5F9, fg: 0x0F172A, muted: 0x64748B, accent: 0xE63946),
        .make(id: "vs-dark", name: "Dark", isDark: true, bg: 0x0F172A, fg: 0xE2E8F0, muted: 0x64748B, accent: 0xE63946),
        .make(id: "synthwave-84", name: "Synthwave '84", isDark: true, bg: 0x262335, fg: 0xFFFFFF, muted: 0x848BBD, accent: 0xFF7EDB),
        .make(id: "dracula", name: "Dracula", isDark: true, bg: 0x282A36, fg: 0xF8F8F2, muted: 0x6272A4, accent: 0xBD93F9),
        .make(id: "one-dark", name: "One Dark", isDark: true, bg: 0x282C34, fg: 0xABB2BF, muted: 0x5C6370, accent: 0x61AFEF),
        .make(id: "night-owl", name: "Night Owl", isDark: true, bg: 0x011627, fg: 0xD6DEEB, muted: 0x637777, accent: 0x82AAFF),
        .make(id: "github-dark", name: "GitHub Dark", isDark: true, bg: 0x0D1117, fg: 0xC9D1D9, muted: 0x8B949E, accent: 0x58A6FF),
        .make(id: "monokai", name: "Monokai", isDark: true, bg: 0x272822, fg: 0xF8F8F2, muted: 0x75715E, accent: 0xF92672),
        .make(id: "nord", name: "Nord", isDark: true, bg: 0x2E3440, fg: 0xD8DEE9, muted: 0x616E88, accent: 0x88C0D0),
        .make(id: "cobalt2", name: "Cobalt2", isDark: true, bg: 0x193549, fg: 0xFFFFFF, muted: 0x0088FF, accent: 0xFFC600),
        .make(id: "material", name: "Material", isDark: true, bg: 0x263238, fg: 0xEEFFFF, muted: 0x546E7A, accent: 0x89DDFF),
        .make(id: "tokyo-night", name: "Tokyo Night", isDark: true, bg: 0x1A1B26, fg: 0xC0CAF5, muted: 0x565F89, accent: 0x7AA2F7),
        .make(id: "hc-black", name: "High Contrast Dark", isDark: true, bg: 0x000000, fg: 0xFFFFFF, muted: 0x808080, accent: 0xFFFF00),
        .make(id: "hc-light", name: "High Contrast Light", isDark: false, bg: 0xFFFFFF, fg: 0x000000, muted: 0x808080, accent: 0x0000FF),
    ]

    static func byId(_ id: String) -> ConstructTheme {
        all.first { $0.id == id } ?? all[0]
    }
}

private struct ConstructThemeKey: EnvironmentKey {
    static let defaultValue: ConstructTheme = ConstructThemes.byId("vs")
}

extension EnvironmentValues {
    var constructTheme: ConstructTheme {
        get { self[ConstructThemeKey.self] }
        set { self[ConstructThemeKey.self] = newValue }
    }
}

extension Color {
    /// Builds a Color from a 0xRRGGBB integer.
    static func hex(_ value: UInt32) -> Color {
        Color(.sRGB,
              red: Double((value >> 16) & 0xFF) / 255,
              green: Double((value >> 8) & 0xFF) / 255,
              blue: Double(value & 0xFF) / 255,
              opacity: 1)
    }

    /// Linearly blends two hex colors: t=0 → a, t=1 → b.
    static func blend(_ a: UInt32, _ b: UInt32, _ t: Double) -> Color {
        func ch(_ v: UInt32, _ s: Int) -> Double { Double((v >> s) & 0xFF) }
        let r = ch(a, 16) + (ch(b, 16) - ch(a, 16)) * t
        let g = ch(a, 8) + (ch(b, 8) - ch(a, 8)) * t
        let bl = ch(a, 0) + (ch(b, 0) - ch(a, 0)) * t
        return Color(.sRGB, red: r / 255, green: g / 255, blue: bl / 255, opacity: 1)
    }

    /// Darkens a hex color toward black — matches the host's `darkenColor`.
    static func darken(_ v: UInt32, _ amount: Double) -> Color {
        func ch(_ s: Int) -> Double { Double((v >> s) & 0xFF) * (1 - amount) }
        return Color(.sRGB, red: ch(16) / 255, green: ch(8) / 255, blue: ch(0) / 255, opacity: 1)
    }

    /// Lightens a hex color toward white — matches the host's `lightenColor`.
    static func lighten(_ v: UInt32, _ amount: Double) -> Color {
        func ch(_ s: Int) -> Double { let c = Double((v >> s) & 0xFF); return c + (255 - c) * amount }
        return Color(.sRGB, red: ch(16) / 255, green: ch(8) / 255, blue: ch(0) / 255, opacity: 1)
    }
}
