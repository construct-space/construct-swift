import SwiftUI

/// The actual Construct brand mark (the "O" ring + bar), rendered from the
/// real logo SVG (construct-mark, viewBox 533×533) as a tinted vector — not an
/// invented glyph. Even-odd fill makes the ring's hole.
struct ConstructLogo: View {
    var color: Color
    var size: CGFloat = 22

    var body: some View {
        ConstructMarkShape()
            .fill(color, style: FillStyle(eoFill: true))
            .frame(width: size, height: size)
    }
}

/// The construct-mark.svg path (two subpaths: the O ring + the underline bar).
private struct ConstructMarkShape: Shape {
    // Verbatim from construct-mark.svg (web/my construct-mark.svg).
    private static let svgPaths = [
        "M266.5 410.156C230.912 410.156 199.106 402.203 171.081 386.297C143.056 370.39 121.036 348.519 105.022 320.684C89.0072 292.848 81 261.256 81 225.909C81 190.12 89.0072 158.308 105.022 130.472C121.036 102.636 143.056 80.7655 171.081 64.8593C199.106 48.9531 230.912 41 266.5 41C302.087 41 333.671 48.9531 361.252 64.8593C389.277 80.7655 411.297 102.636 427.311 130.472C443.326 158.308 451.555 190.12 452 225.909C452 261.256 443.77 292.848 427.311 320.684C411.297 348.519 389.277 370.39 361.252 386.297C333.671 402.203 302.087 410.156 266.5 410.156ZM266.5 363.763C292.301 363.763 315.433 357.798 335.896 345.868C356.359 333.939 372.373 317.591 383.939 296.824C395.505 276.058 401.288 252.42 401.288 225.909C401.288 199.399 395.505 175.761 383.939 154.994C372.373 133.786 356.359 117.217 335.896 105.287C315.433 93.3579 292.301 87.393 266.5 87.393C240.699 87.393 217.567 93.3579 197.104 105.287C176.641 117.217 160.405 133.786 148.394 154.994C136.828 175.761 131.045 199.399 131.045 225.909C131.045 252.42 136.828 276.058 148.394 296.824C160.405 317.591 176.641 333.939 197.104 345.868C217.567 357.798 240.699 363.763 266.5 363.763Z",
        "M378.22 451.578C393.077 451.578 405.121 460.85 405.121 472.289C405.121 483.727 393.077 493 378.22 493H160.945C146.089 493 134.044 483.727 134.044 472.289C134.044 460.85 146.089 451.578 160.945 451.578H378.22Z",
    ]

    func path(in rect: CGRect) -> Path {
        let scale = min(rect.width, rect.height) / 533.0
        var path = Path()
        for d in Self.svgPaths { Self.append(d, to: &path) }
        return path.applying(CGAffineTransform(scaleX: scale, y: scale))
    }

    /// Minimal absolute-command SVG path parser (M/L/H/V/C/Z) — enough for the
    /// construct mark.
    private static func append(_ d: String, to path: inout Path) {
        let scanner = Scanner(string: d)
        scanner.charactersToBeSkipped = CharacterSet(charactersIn: " ,\n\t")
        var cmd: Character = " "
        var current = CGPoint.zero
        var start = CGPoint.zero
        let cmds = CharacterSet(charactersIn: "MLHVCZmlhvcz")

        func num() -> CGFloat { CGFloat(scanner.scanDouble() ?? 0) }

        while !scanner.isAtEnd {
            if let c = scanner.scanCharacters(from: cmds), let last = c.last {
                cmd = last
            }
            switch cmd {
            case "M": current = CGPoint(x: num(), y: num()); start = current; path.move(to: current); cmd = "L"
            case "L": current = CGPoint(x: num(), y: num()); path.addLine(to: current)
            case "H": current.x = num(); path.addLine(to: current)
            case "V": current.y = num(); path.addLine(to: current)
            case "C":
                let c1 = CGPoint(x: num(), y: num())
                let c2 = CGPoint(x: num(), y: num())
                let end = CGPoint(x: num(), y: num())
                path.addCurve(to: end, control1: c1, control2: c2); current = end
            case "Z", "z": path.closeSubpath(); current = start
            default:
                // Unknown — bail to avoid an infinite loop.
                return
            }
        }
    }
}
