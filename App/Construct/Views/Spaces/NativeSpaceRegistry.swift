import SwiftUI
import ConstructCore

/// A first-party space implemented natively in SwiftUI (no webview). Looked up
/// by id before falling back to the WebUI space runner.
struct NativeCoreSpace: Identifiable {
    let id: String
    let name: String
    let icon: String          // SF Symbol
    /// True for the host's built-in core spaces (frontend/spaces/*) — the agent
    /// surfaces and management consoles. False for native utility apps.
    let isCore: Bool
    let description: String
    let make: () -> AnyView
}

/// Registry of native spaces. The `core` group ports the host-native spaces in
/// `construct-app/frontend/spaces/*` (Ask, Builder, Project, Space Developer,
/// Org); the `utilities` group is local-first native apps that shadow the
/// matching marketplace spaces (Notes, Calculator, Clock) or stand alone.
@MainActor
enum NativeSpaceRegistry {
    /// Host-native core spaces (frontend/spaces/*) — agent surfaces + consoles.
    static let core: [NativeCoreSpace] = [
        NativeCoreSpace(
            id: "ask", name: "Ask", icon: "sparkles", isCore: true,
            description: "Ask questions and get answers — your general thinking space.",
            make: { AnyView(AgentChatView(agentId: "ask", title: "Ask",
                emptyTitle: "What's on your mind?",
                emptySubtitle: "Think, research, brainstorm, or just talk.")) }
        ),
        NativeCoreSpace(
            id: "builder", name: "Builder", icon: "hammer", isCore: true,
            description: "Plans, builds, and verifies general software — sites, apps.",
            make: { AnyView(BuilderSpace()) }
        ),
        NativeCoreSpace(
            id: "project", name: "Developer", icon: "chevron.left.forwardslash.chevron.right", isCore: true,
            description: "Build, ship, and verify apps and Spaces — Builder, SpaceKit, and your projects.",
            make: { AnyView(ProjectSpace()) }
        ),
        NativeCoreSpace(
            id: "space-developer", name: "Space Developer", icon: "shippingbox", isCore: true,
            description: "Plans, builds, and verifies Construct Spaces.",
            make: { AnyView(BuilderSpace(agentId: "space-developer", title: "Space Developer",
                                         icon: "shippingbox", emptyTitle: "Build a Space")) }
        ),
        NativeCoreSpace(
            id: "org", name: "Organization", icon: "building.2", isCore: true,
            description: "Manage members, departments, teams, roles, and invitations.",
            make: { AnyView(OrgConsoleSpace()) }
        ),
        NativeCoreSpace(
            id: "org-project", name: "Org Projects", icon: "folder.fill.badge.person.crop", isCore: true,
            description: "Org-wide projects — track and coordinate shared work.",
            make: { AnyView(OrgProjectsSpace()) }
        ),
    ]

    /// Native utility apps (local-first; shadow the matching marketplace space
    /// where one exists).
    static let utilities: [NativeCoreSpace] = [
        NativeCoreSpace(id: "notes", name: "Notes", icon: "note.text", isCore: false,
            description: "Fast native notes — markdown, stored on your Mac.",
            make: { AnyView(NotesSpace()) }),
        NativeCoreSpace(id: "calculator", name: "Calculator", icon: "function", isCore: false,
            description: "A native four-function calculator.",
            make: { AnyView(CalculatorSpace()) }),
        NativeCoreSpace(id: "clock", name: "Clock", icon: "clock", isCore: false,
            description: "World clock with saved cities, native and always ticking.",
            make: { AnyView(ClockSpace()) }),
        NativeCoreSpace(id: "units", name: "Unit Converter", icon: "arrow.left.arrow.right", isCore: false,
            description: "Convert length, mass, temperature, volume, and speed — offline.",
            make: { AnyView(UnitConverterSpace()) }),
    ]

    static let all: [NativeCoreSpace] = core + utilities

    static func space(for id: String) -> NativeCoreSpace? {
        all.first { $0.id == id }
    }

    static var ids: Set<String> { Set(all.map(\.id)) }
}
