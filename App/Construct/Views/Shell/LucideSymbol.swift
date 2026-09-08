import Foundation

/// Best-effort mapping from a manifest icon string (e.g. "i-lucide-map") to an
/// SF Symbol name, so native chrome can render a space's icons. Falls back to a
/// cube. Extend the table as needed.
enum LucideSymbol {
    static func sfSymbol(for icon: String?) -> String {
        guard let icon else { return "cube" }
        // Strip iconify prefixes: "i-lucide-map" / "lucide:map" → "map".
        var name = icon
        for prefix in ["i-lucide-", "lucide:", "i-", "lucide-"] {
            if name.hasPrefix(prefix) { name = String(name.dropFirst(prefix.count)); break }
        }
        return table[name] ?? "cube"
    }

    private static let table: [String: String] = [
        "map": "map", "map-pin": "mappin.circle", "map-pinned": "mappin.and.ellipse",
        "settings": "gearshape", "gear": "gearshape", "cog": "gearshape",
        "home": "house", "house": "house",
        "search": "magnifyingglass", "mail": "envelope", "inbox": "tray",
        "calendar": "calendar", "clock": "clock", "bell": "bell",
        "cloud": "cloud", "cloud-sun": "cloud.sun", "sun": "sun.max", "cloud-rain": "cloud.rain",
        "users": "person.2", "user": "person", "user-circle": "person.crop.circle",
        "file": "doc", "file-text": "doc.text", "files": "doc.on.doc", "folder": "folder",
        "message-square": "message", "messages-square": "bubble.left.and.bubble.right",
        "chat": "bubble.left", "phone": "phone", "video": "video",
        "star": "star", "heart": "heart", "bookmark": "bookmark",
        "list": "list.bullet", "grid": "square.grid.2x2", "layout-grid": "square.grid.2x2",
        "kanban": "rectangle.split.3x1", "board": "rectangle.split.3x1",
        "check": "checkmark", "check-circle": "checkmark.circle", "plus": "plus",
        "trash": "trash", "trash-2": "trash", "edit": "pencil", "pencil": "pencil",
        "chart": "chart.bar", "bar-chart": "chart.bar", "line-chart": "chart.xyaxis.line",
        "dollar-sign": "dollarsign.circle", "credit-card": "creditcard", "wallet": "wallet.pass",
        "package": "shippingbox", "box": "cube", "shopping-cart": "cart", "bag": "bag",
        "image": "photo", "camera": "camera", "music": "music.note", "radio": "dot.radiowaves.left.and.right",
        "globe": "globe", "link": "link", "compass": "safari", "navigation": "location",
        "briefcase": "briefcase", "building": "building.2", "store": "storefront",
        "book": "book", "library": "books.vertical", "graduation-cap": "graduationcap",
        "activity": "waveform.path.ecg", "heart-pulse": "heart.text.square",
        "stethoscope": "cross.case", "pill": "pills", "tooth": "mouth",
        "wind": "wind", "droplets": "drop", "sunrise": "sunrise", "sunset": "sunset",
        "refresh-cw": "arrow.clockwise", "rotate-cw": "arrow.clockwise",
    ]
}
