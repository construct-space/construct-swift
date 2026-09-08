import SwiftUI
import ConstructCore

/// A native core space: a multi-category unit converter. Pure local computation
/// (no backend, no sync to diverge), first-party — a good fit for the native
/// hybrid model alongside Calculator and Clock.
struct UnitConverterSpace: View {
    @Environment(\.constructTheme) private var theme

    struct Unit: Identifiable, Hashable { let id: String; let name: String; let factor: Double }
    struct Category: Identifiable, Hashable {
        let id: String, name: String, icon: String
        let units: [Unit]
        /// Linear categories convert via a factor to a base unit; temperature
        /// is special-cased.
        let isTemperature: Bool
    }

    // Factors are "how many base units per 1 of this unit".
    private let categories: [Category] = [
        Category(id: "length", name: "Length", icon: "ruler", units: [
            .init(id: "mm", name: "Millimeters", factor: 0.001),
            .init(id: "cm", name: "Centimeters", factor: 0.01),
            .init(id: "m", name: "Meters", factor: 1),
            .init(id: "km", name: "Kilometers", factor: 1000),
            .init(id: "in", name: "Inches", factor: 0.0254),
            .init(id: "ft", name: "Feet", factor: 0.3048),
            .init(id: "mi", name: "Miles", factor: 1609.344),
        ], isTemperature: false),
        Category(id: "mass", name: "Mass", icon: "scalemass", units: [
            .init(id: "g", name: "Grams", factor: 1),
            .init(id: "kg", name: "Kilograms", factor: 1000),
            .init(id: "oz", name: "Ounces", factor: 28.3495),
            .init(id: "lb", name: "Pounds", factor: 453.592),
            .init(id: "st", name: "Stone", factor: 6350.29),
        ], isTemperature: false),
        Category(id: "temp", name: "Temperature", icon: "thermometer.medium", units: [
            .init(id: "C", name: "Celsius", factor: 1),
            .init(id: "F", name: "Fahrenheit", factor: 1),
            .init(id: "K", name: "Kelvin", factor: 1),
        ], isTemperature: true),
        Category(id: "volume", name: "Volume", icon: "drop", units: [
            .init(id: "ml", name: "Milliliters", factor: 0.001),
            .init(id: "l", name: "Liters", factor: 1),
            .init(id: "tsp", name: "Teaspoons", factor: 0.00492892),
            .init(id: "tbsp", name: "Tablespoons", factor: 0.0147868),
            .init(id: "cup", name: "Cups", factor: 0.236588),
            .init(id: "gal", name: "Gallons (US)", factor: 3.78541),
        ], isTemperature: false),
        Category(id: "speed", name: "Speed", icon: "gauge.with.dots.needle.67percent", units: [
            .init(id: "kmh", name: "km/h", factor: 1),
            .init(id: "mph", name: "mph", factor: 1.609344),
            .init(id: "ms", name: "m/s", factor: 3.6),
            .init(id: "kn", name: "Knots", factor: 1.852),
        ], isTemperature: false),
    ]

    @State private var categoryId = "length"
    @State private var fromId = "m"
    @State private var toId = "ft"
    @State private var input = "1"

    private var category: Category { categories.first { $0.id == categoryId } ?? categories[0] }
    private var fromUnit: Unit { category.units.first { $0.id == fromId } ?? category.units[0] }
    private var toUnit: Unit { category.units.first { $0.id == toId } ?? category.units[0] }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Unit Converter").font(.system(size: 22, weight: .bold)).foregroundStyle(theme.foreground)

                categoryPicker

                VStack(spacing: 12) {
                    unitField(label: "From", unitId: $fromId, value: $input, editable: true)
                    HStack {
                        Spacer()
                        Button(action: swap) {
                            Image(systemName: "arrow.up.arrow.down").foregroundStyle(theme.accent)
                                .padding(8).background(Circle().fill(theme.inputBg))
                        }.buttonStyle(.plain)
                        Spacer()
                    }
                    unitField(label: "To", unitId: $toId, value: .constant(resultString), editable: false)
                }
            }
            .padding(28)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
        .background(theme.surface)
        .onChange(of: categoryId) { _, _ in
            fromId = category.units.first?.id ?? ""
            toId = category.units.dropFirst().first?.id ?? fromId
        }
    }

    private var categoryPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(categories) { c in
                    Button { categoryId = c.id } label: {
                        Label(c.name, systemImage: c.icon)
                            .font(.system(size: 12, weight: .medium))
                            .padding(.horizontal, 12).padding(.vertical, 7)
                            .background(Capsule().fill(categoryId == c.id ? theme.accent : theme.inputBg))
                            .foregroundStyle(categoryId == c.id ? theme.accentForeground : theme.foreground)
                    }.buttonStyle(.plain)
                }
            }
        }
    }

    private func unitField(label: String, unitId: Binding<String>, value: Binding<String>, editable: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label.uppercased()).font(.system(size: 10, weight: .semibold)).foregroundStyle(theme.muted)
            HStack(spacing: 10) {
                if editable {
                    TextField("0", text: value)
                        .textFieldStyle(.plain).font(.system(size: 28, weight: .light, design: .rounded))
                        .foregroundStyle(theme.foreground)
                } else {
                    Text(value.wrappedValue).font(.system(size: 28, weight: .light, design: .rounded))
                        .foregroundStyle(theme.foreground).frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                Picker("", selection: unitId) {
                    ForEach(category.units) { Text($0.name).tag($0.id) }
                }.labelsHidden().fixedSize()
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 8).fill(theme.inputBg))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(theme.border))
        }
    }

    private func swap() { let t = fromId; fromId = toId; toId = t }

    private var resultString: String {
        guard let v = Double(input.replacingOccurrences(of: ",", with: ".")) else { return "—" }
        let result = category.isTemperature
            ? convertTemperature(v, from: fromId, to: toId)
            : v * fromUnit.factor / toUnit.factor
        return format(result)
    }

    private func convertTemperature(_ v: Double, from: String, to: String) -> Double {
        // Normalize to Celsius, then to target.
        let c: Double
        switch from { case "F": c = (v - 32) * 5 / 9; case "K": c = v - 273.15; default: c = v }
        switch to { case "F": return c * 9 / 5 + 32; case "K": return c + 273.15; default: return c }
    }

    private func format(_ v: Double) -> String {
        if v.isNaN || v.isInfinite { return "—" }
        if abs(v) >= 1e9 || (abs(v) < 1e-4 && v != 0) { return String(format: "%.4g", v) }
        let rounded = (v * 1e6).rounded() / 1e6
        return rounded == rounded.rounded() ? String(Int64(rounded)) : String(format: "%g", rounded)
    }
}
