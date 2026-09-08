import SwiftUI
import ConstructCore

/// A native core space: a four-function calculator. Mirrors the first-party
/// `calculator` store space, rendered natively in SwiftUI (the hybrid model).
struct CalculatorSpace: View {
    @Environment(\.constructTheme) private var theme

    @State private var display = "0"
    @State private var accumulator: Double?
    @State private var pendingOp: Op?
    @State private var replace = true   // next digit starts a fresh entry

    enum Op: String, CaseIterable { case add = "+", subtract = "−", multiply = "×", divide = "÷" }

    private let rows: [[Key]] = [
        [.clear, .negate, .percent, .op(.divide)],
        [.digit("7"), .digit("8"), .digit("9"), .op(.multiply)],
        [.digit("4"), .digit("5"), .digit("6"), .op(.subtract)],
        [.digit("1"), .digit("2"), .digit("3"), .op(.add)],
        [.digit("0"), .dot, .equals],
    ]

    var body: some View {
        VStack(spacing: 12) {
            displayView
            keypad
        }
        .padding(20)
        .frame(maxWidth: 420, maxHeight: .infinity, alignment: .bottom)
        .frame(maxWidth: .infinity)
        .background(theme.surface)
    }

    private var displayView: some View {
        Text(display)
            .font(.system(size: 56, weight: .light, design: .rounded))
            .foregroundStyle(theme.foreground)
            .lineLimit(1).minimumScaleFactor(0.4)
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.horizontal, 8)
            .textSelection(.enabled)
    }

    private var keypad: some View {
        VStack(spacing: 10) {
            ForEach(rows.indices, id: \.self) { r in
                HStack(spacing: 10) {
                    ForEach(rows[r].indices, id: \.self) { c in
                        keyButton(rows[r][c])
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func keyButton(_ key: Key) -> some View {
        Button { tap(key) } label: {
            Text(key.label)
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(key.foreground(theme, active: isActive(key)))
                .frame(maxWidth: .infinity)
                .frame(height: 64)
                .frame(width: key.isWide ? nil : 64)
                .background(RoundedRectangle(cornerRadius: 10).fill(key.background(theme, active: isActive(key))))
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
    }

    private func isActive(_ key: Key) -> Bool {
        if case let .op(o) = key { return pendingOp == o && replace }
        return false
    }

    // MARK: Input

    enum Key: Hashable {
        case digit(String), dot, op(Op), equals, clear, negate, percent
        var isWide: Bool { if case .digit("0") = self { return true }; return false }
        var label: String {
            switch self {
            case .digit(let d): return d
            case .dot: return "."
            case .op(let o): return o.rawValue
            case .equals: return "="
            case .clear: return "AC"
            case .negate: return "±"
            case .percent: return "%"
            }
        }
        func background(_ t: ConstructTheme, active: Bool) -> Color {
            switch self {
            case .op, .equals: return active ? .white : t.accent
            case .clear, .negate, .percent: return t.inputBg
            default: return t.canvasBg
            }
        }
        func foreground(_ t: ConstructTheme, active: Bool) -> Color {
            switch self {
            case .op, .equals: return active ? t.accent : t.accentForeground
            default: return t.foreground
            }
        }
    }

    private func tap(_ key: Key) {
        switch key {
        case .digit(let d): inputDigit(d)
        case .dot: inputDot()
        case .op(let o): setOp(o)
        case .equals: equalsPressed()
        case .clear: clearAll()
        case .negate: negate()
        case .percent: percent()
        }
    }

    private func inputDigit(_ d: String) {
        if replace { display = d; replace = false }
        else if display == "0" { display = d }
        else { display += d }
    }

    private func inputDot() {
        if replace { display = "0."; replace = false }
        else if !display.contains(".") { display += "." }
    }

    private func setOp(_ o: Op) {
        if let pending = pendingOp, !replace { compute(pending) }
        else { accumulator = current }
        pendingOp = o
        replace = true
    }

    private func equalsPressed() {
        guard let pending = pendingOp else { return }
        compute(pending)
        pendingOp = nil
        replace = true
    }

    private func compute(_ op: Op) {
        let lhs = accumulator ?? 0, rhs = current
        let result: Double
        switch op {
        case .add: result = lhs + rhs
        case .subtract: result = lhs - rhs
        case .multiply: result = lhs * rhs
        case .divide: result = rhs == 0 ? .nan : lhs / rhs
        }
        accumulator = result
        display = format(result)
    }

    private func clearAll() {
        display = "0"; accumulator = nil; pendingOp = nil; replace = true
    }

    private func negate() { display = format(-current) }

    private func percent() { display = format(current / 100) }

    private var current: Double { Double(display) ?? 0 }

    private func format(_ v: Double) -> String {
        if v.isNaN { return "Error" }
        if v == v.rounded() && abs(v) < 1e15 { return String(Int64(v)) }
        return String(format: "%g", v)
    }
}
