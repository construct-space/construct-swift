import Foundation
import Observation

/// Local projects, mirroring the Tauri project store. Projects are folders under
/// a projects root (default `~/ConstructProjects`); a Construct project is
/// marked by `.construct/project.json`. Builder / Space Developer / TUI open
/// scoped to the selected project's folder (project_dir).
///
/// Personal projects are filesystem-only (no server sync) — see the project
/// memory note. Org projects (source-api) are a separate surface.
@MainActor
@Observable
public final class ProjectStore {
    public private(set) var root: URL
    public private(set) var projects: [Project] = []
    /// The project Builder/Space-Dev/TUI operate within when launched.
    public var current: Project?

    private let rootKey = "construct_projects_root"
    private let externalKey = "construct.projects.external"
    /// Folders opened via "Open Folder" that live outside the projects root.
    public private(set) var externalPaths: [String] = []

    public init() {
        if let saved = UserDefaults.standard.string(forKey: rootKey), !saved.isEmpty {
            root = URL(fileURLWithPath: saved)
        } else {
            root = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("ConstructProjects")
        }
    }

    public func setRoot(_ url: URL) {
        root = url
        UserDefaults.standard.set(url.path, forKey: rootKey)
        scan()
    }

    /// Scans the root (and opened external folders) for projects. Each dir is a
    /// project; `.construct/project.json` carries its saved name/kind.
    public func scan() {
        let fm = FileManager.default
        externalPaths = UserDefaults.standard.array(forKey: externalKey) as? [String] ?? []
        try? fm.createDirectory(at: root, withIntermediateDirectories: true)
        let ignored: Set<String> = [".DS_Store"]
        var dirs: [URL] = []
        if let names = try? fm.contentsOfDirectory(atPath: root.path) {
            dirs += names.filter { !ignored.contains($0) && !$0.hasPrefix(".") }.map { root.appendingPathComponent($0) }
        }
        dirs += externalPaths.map { URL(fileURLWithPath: $0) }
        var seen = Set<String>()
        projects = dirs.compactMap { dir -> Project? in
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: dir.path, isDirectory: &isDir), isDir.boolValue,
                  seen.insert(dir.path).inserted else { return nil }
            let meta = readMeta(dir)
            let attrs = try? fm.attributesOfItem(atPath: dir.path)
            return Project(id: dir.path, name: meta?.name ?? dir.lastPathComponent, path: dir.path, kind: .local,
                           spaces: meta?.spaces ?? [], updatedAt: attrs?[.modificationDate] as? Date)
        }.sorted { ($0.updatedAt ?? .distantPast) > ($1.updatedAt ?? .distantPast) }
        if let cur = current, !projects.contains(where: { $0.id == cur.id }) { current = nil }
    }

    /// Adds an existing folder as a project (the "Open Folder" flow), persisting
    /// it if it lives outside the projects root, and selects it.
    @discardableResult
    public func openFolder(_ url: URL) -> Project {
        if !url.path.hasPrefix(root.path) && !externalPaths.contains(url.path) {
            externalPaths.append(url.path)
            UserDefaults.standard.set(externalPaths, forKey: externalKey)
        }
        scan()
        let project = projects.first { $0.path == url.path }
            ?? Project(id: url.path, name: url.lastPathComponent, path: url.path, kind: .local)
        current = project
        return project
    }

    /// Creates a new project folder under the root + a `.construct/project.json`.
    @discardableResult
    public func create(name: String, description: String? = nil, kind: String? = nil) throws -> Project {
        let safe = name.trimmingCharacters(in: .whitespaces)
        let dir = root.appendingPathComponent(safe)
        let fm = FileManager.default
        try fm.createDirectory(at: dir.appendingPathComponent(".construct"), withIntermediateDirectories: true)
        let meta = ProjectMeta(name: safe, description: description, spaces: [], kind: kind)
        if let data = try? JSONEncoder().encode(meta) {
            try? data.write(to: dir.appendingPathComponent(".construct/project.json"))
        }
        scan()
        let project = projects.first { $0.path == dir.path }
            ?? Project(id: dir.path, name: safe, path: dir.path, kind: .local)
        current = project
        return project
    }

    public func select(_ project: Project) { current = project }

    // MARK: Project type detection

    /// What a project is, deciding which build agent opens it. Mirrors
    /// ProjectDetailPage.vue's projectType: a Construct Space → Space Developer;
    /// a native app or website → Builder.
    public enum Detected: String, Sendable { case space, app, web }

    /// The build agent + label/icon for a project, read from `.construct`
    /// (kind) and light filesystem probes — so we open with the right one,
    /// not all three.
    public func detect(_ project: Project) -> Detected {
        guard let path = project.path else { return .web }
        let fm = FileManager.default
        let url = URL(fileURLWithPath: path)
        func exists(_ rel: String) -> Bool { fm.fileExists(atPath: url.appendingPathComponent(rel).path) }

        // 1. Explicit kind from .construct/project.json.
        if let meta = readMeta(url), meta.kind == "space-project" { return .space }
        // 2. Construct Space markers.
        if exists("space.manifest.json") { return .space }
        if let entries = try? fm.contentsOfDirectory(atPath: path),
           entries.contains(where: { $0.hasPrefix("space-") }) { return .space }
        // 3. Native app frameworks → app.
        if exists("pubspec.yaml") { return .app }                            // Flutter
        if let entries = try? fm.contentsOfDirectory(atPath: path),
           entries.contains(where: { $0.hasSuffix(".xcodeproj") || $0.hasSuffix(".xcworkspace") }) { return .app }
        // 4. Default: a website / general project → Builder.
        return .web
    }

    /// (agentId, label, SF Symbol) of the primary build agent for a project.
    public func primaryAgent(for project: Project) -> (id: String, label: String, icon: String) {
        switch detect(project) {
        case .space: return ("space-developer", "Space Developer", "shippingbox")
        case .app, .web: return ("builder", "Builder", "hammer")
        }
    }

    // MARK: project.json

    private struct ProjectMeta: Codable { var name: String; var description: String?; var spaces: [String]; var kind: String? }

    private func readMeta(_ dir: URL) -> ProjectMeta? {
        let url = dir.appendingPathComponent(".construct/project.json")
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(ProjectMeta.self, from: data)
    }
}
