import SwiftUI
import ConstructCore

/// A native core space: a world clock with saved cities. Mirrors the first-party
/// `clock` store space, rendered natively (the hybrid model). Cities persist to
/// the profile dir; the display ticks once a second.
struct ClockSpace: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.constructTheme) private var theme

    struct City: Codable, Identifiable, Hashable {
        var id = UUID()
        var name: String
        var timeZoneId: String
    }

    @State private var cities: [City] = []
    @State private var now = Date()
    @State private var showAdd = false
    @State private var pendingDelete: City?

    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var fileURL: URL {
        env.paths.profileDir(env.profiles.activeProfileId)
            .appendingPathComponent("native", isDirectory: true)
            .appendingPathComponent("clock.json")
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                localCard
                if !cities.isEmpty {
                    Text("WORLD CLOCK").font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(theme.muted).frame(maxWidth: .infinity, alignment: .leading)
                    ForEach(cities) { city in cityRow(city) }
                }
            }
            .padding(24)
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
        }
        .background(theme.surface)
        .onReceive(tick) { now = $0 }
        .onAppear(perform: load)
        .toolbar { ToolbarItem { Button { showAdd = true } label: { Image(systemName: "plus") } } }
        .overlay(alignment: .bottomTrailing) {
            Button { showAdd = true } label: {
                Image(systemName: "plus.circle.fill").font(.system(size: 40)).foregroundStyle(theme.accent)
            }
            .buttonStyle(.plain).padding(24)
        }
        .sheet(isPresented: $showAdd) { addSheet }
        .confirmationDialog("Remove this clock?",
                            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
                            titleVisibility: .visible) {
            Button("Remove", role: .destructive) {
                if let c = pendingDelete { cities.removeAll { $0.id == c.id }; save() }
                pendingDelete = nil
            }
            Button("Cancel", role: .cancel) { pendingDelete = nil }
        }
    }

    // MARK: Local time hero

    private var localCard: some View {
        VStack(spacing: 6) {
            Text(timeString(.current)).font(.system(size: 64, weight: .thin, design: .rounded))
                .foregroundStyle(theme.foreground).monospacedDigit()
            Text(dateString(.current)).font(.system(size: 15)).foregroundStyle(theme.muted)
            Text(localLabel).font(.system(size: 12, weight: .medium)).foregroundStyle(theme.accent)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .background(RoundedRectangle(cornerRadius: 10).fill(theme.inputBg))
    }

    private var localLabel: String {
        TimeZone.current.localizedName(for: .standard, locale: .current) ?? TimeZone.current.identifier
    }

    private func cityRow(_ city: City) -> some View {
        let tz = TimeZone(identifier: city.timeZoneId) ?? .current
        return HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(city.name).font(.system(size: 16, weight: .medium)).foregroundStyle(theme.foreground)
                Text(offsetLabel(tz)).font(.system(size: 11)).foregroundStyle(theme.muted)
            }
            Spacer()
            Text(timeString(tz)).font(.system(size: 30, weight: .light, design: .rounded))
                .foregroundStyle(theme.foreground).monospacedDigit()
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 8).fill(theme.inputBg.opacity(0.6)))
        .contextMenu { Button("Remove", role: .destructive) { pendingDelete = city } }
    }

    // MARK: Add sheet

    @State private var query = ""
    private var addSheet: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Add City").font(.system(size: 14, weight: .semibold)).foregroundStyle(theme.foreground)
                Spacer()
                Button("Done") { showAdd = false }.buttonStyle(.plain).foregroundStyle(theme.accent)
            }.padding(14)
            Divider().overlay(theme.border)
            TextField("Search time zones…", text: $query)
                .textFieldStyle(.plain).padding(10)
                .background(RoundedRectangle(cornerRadius: 8).fill(theme.inputBg)).padding(12)
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(matches, id: \.self) { id in
                        Button { add(id); showAdd = false; query = "" } label: {
                            HStack {
                                Text(cityName(id)).foregroundStyle(theme.foreground)
                                Spacer()
                                Text(offsetLabel(TimeZone(identifier: id) ?? .current)).font(.system(size: 11)).foregroundStyle(theme.muted)
                            }
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .frame(maxWidth: .infinity)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 8)
            }
        }
        .frame(width: 420, height: 480)
        .background(theme.surface)
    }

    private var matches: [String] {
        let all = TimeZone.knownTimeZoneIdentifiers
        guard !query.isEmpty else { return Array(all.prefix(50)) }
        let q = query.lowercased()
        return all.filter { $0.lowercased().contains(q) }.prefix(80).map { $0 }
    }

    // MARK: Formatting

    private func timeString(_ tz: TimeZone) -> String { formatted(now, tz, "HH:mm:ss") }
    private func dateString(_ tz: TimeZone) -> String { formatted(now, tz, "EEEE, MMM d") }
    private func formatted(_ date: Date, _ tz: TimeZone, _ fmt: String) -> String {
        let df = DateFormatter(); df.dateFormat = fmt; df.timeZone = tz; return df.string(from: date)
    }
    private func offsetLabel(_ tz: TimeZone) -> String {
        let secs = tz.secondsFromGMT(for: now)
        let h = secs / 3600, m = abs(secs % 3600) / 60
        let sign = secs >= 0 ? "+" : "−"
        return "GMT\(sign)\(abs(h))" + (m == 0 ? "" : String(format: ":%02d", m))
    }
    private func cityName(_ id: String) -> String {
        (id.split(separator: "/").last.map(String.init) ?? id).replacingOccurrences(of: "_", with: " ")
    }

    // MARK: Data

    private func add(_ id: String) {
        guard !cities.contains(where: { $0.timeZoneId == id }) else { return }
        cities.append(City(name: cityName(id), timeZoneId: id)); save()
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([City].self, from: data) else { return }
        cities = decoded
    }

    private func save() {
        let dir = fileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(cities) { try? data.write(to: fileURL, options: .atomic) }
    }
}
