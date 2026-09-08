import SwiftUI
import ConstructCore

/// A native core space: fast SwiftUI notes, persisted to the profile dir.
/// Demonstrates the hybrid model — first-party core spaces run natively.
struct NotesSpace: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.constructTheme) private var theme

    struct Note: Codable, Identifiable, Hashable {
        var id = UUID()
        var title: String = "Untitled"
        var body: String = ""
        var updatedAt: Date = Date()
    }

    @State private var notes: [Note] = []
    @State private var selection: UUID?
    @State private var pendingDelete: Note?

    private var fileURL: URL {
        let dir = env.paths.profileDir(env.profiles.activeProfileId).appendingPathComponent("native", isDirectory: true)
        return dir.appendingPathComponent("notes.json")
    }
    private var selectedIndex: Int? { notes.firstIndex { $0.id == selection } }

    var body: some View {
        HStack(spacing: 0) {
            list.frame(width: 260)
            Divider().overlay(theme.border)
            editor
        }
        .background(theme.surface)
        .onAppear(perform: load)
        .confirmationDialog("Delete note?",
                            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
                            titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                if let n = pendingDelete {
                    notes.removeAll { $0.id == n.id }
                    if selection == n.id { selection = nil }
                    save()
                }
                pendingDelete = nil
            }
            Button("Cancel", role: .cancel) { pendingDelete = nil }
        }
    }

    // MARK: List

    private var list: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Notes").font(.system(size: 13, weight: .semibold)).foregroundStyle(theme.foreground)
                Spacer()
                Button(action: newNote) { Image(systemName: "square.and.pencil") }
                    .buttonStyle(.plain).foregroundStyle(theme.accent)
            }
            .padding(12)
            Divider().overlay(theme.border)
            if notes.isEmpty {
                ContentUnavailableView("No notes", systemImage: "note.text", description: Text("Create your first note."))
                    .frame(maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(notes) { note in
                            row(note)
                        }
                    }
                    .padding(8)
                }
            }
        }
        .background(theme.canvasBg.opacity(0.5))
    }

    private func row(_ note: Note) -> some View {
        Button { selection = note.id } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(note.title.isEmpty ? "Untitled" : note.title)
                    .font(.system(size: 13, weight: .medium)).foregroundStyle(theme.foreground).lineLimit(1)
                Text(note.body.isEmpty ? "No additional text" : note.body)
                    .font(.system(size: 11)).foregroundStyle(theme.muted).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10).padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 8).fill(selection == note.id ? theme.accent.opacity(0.14) : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu { Button("Delete", role: .destructive) { pendingDelete = note } }
    }

    // MARK: Editor

    @ViewBuilder
    private var editor: some View {
        if let idx = selectedIndex {
            VStack(spacing: 0) {
                TextEditor(text: Binding(
                    get: { notes[idx].body },
                    set: { notes[idx].body = $0; notes[idx].title = firstLine($0); notes[idx].updatedAt = Date(); save() }
                ))
                .font(.system(size: 14))
                .scrollContentBackground(.hidden)
                .padding(16)
            }
            .background(theme.surface)
        } else {
            ContentUnavailableView("Select a note", systemImage: "note.text",
                                   description: Text("Choose a note or create a new one."))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(theme.surface)
        }
    }

    // MARK: Data

    private func newNote() {
        let n = Note()
        notes.insert(n, at: 0)
        selection = n.id
        save()
    }

    private func firstLine(_ s: String) -> String {
        let line = s.split(separator: "\n", maxSplits: 1).first.map(String.init) ?? ""
        let trimmed = line.trimmingCharacters(in: CharacterSet(charactersIn: "# ").union(.whitespaces))
        return trimmed.isEmpty ? "Untitled" : String(trimmed.prefix(60))
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([Note].self, from: data) else { return }
        notes = decoded.sorted { $0.updatedAt > $1.updatedAt }
    }

    private func save() {
        let dir = fileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(notes) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }
}
