import AppKit

/// Detects an IntelliJ-style double-tap of Shift (within 400ms) and fires a
/// callback — Left-Shift-Shift toggles the AI assistant, matching the Tauri app.
/// Tracks left/right independently; any other key resets both timers.
@MainActor
final class ShiftShiftMonitor {
    var onLeftDouble: () -> Void = {}
    var onRightDouble: () -> Void = {}

    private var monitor: Any?
    private var lastLeft: TimeInterval = 0
    private var lastRight: TimeInterval = 0
    private let window: TimeInterval = 0.4

    func start() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handle(event)
            return event
        }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    private func handle(_ event: NSEvent) {
        // keyCode 56 = Left Shift, 60 = Right Shift. A "down" is a flagsChanged
        // where .shift is now present.
        let isLeft = event.keyCode == 56
        let isRight = event.keyCode == 60
        guard isLeft || isRight else { return }
        // Only react to the press (shift becoming active), not the release.
        guard event.modifierFlags.contains(.shift) else { return }
        // Ignore if other modifiers are held.
        let others: NSEvent.ModifierFlags = [.command, .control, .option]
        guard event.modifierFlags.isDisjoint(with: others) else { lastLeft = 0; lastRight = 0; return }

        let now = event.timestamp
        if isRight {
            if now - lastRight < window { onRightDouble(); lastRight = 0 } else { lastRight = now }
            lastLeft = 0
        } else {
            if now - lastLeft < window { onLeftDouble(); lastLeft = 0 } else { lastLeft = now }
            lastRight = 0
        }
    }
}
