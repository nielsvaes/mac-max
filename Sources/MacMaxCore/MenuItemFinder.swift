import ApplicationServices
import Foundation

public enum MenuCommand: Hashable, Sendable {
    case fill
    case returnToPreviousSize

    /// The key macOS binds the command to, matched case-insensitively.
    var cmdChar: String {
        switch self {
        case .fill: return "f"
        case .returnToPreviousSize: return "r"
        }
    }
}

/// Locates macOS's own window-tiling menu commands inside another application.
///
/// The match is on the keyboard shortcut rather than the title, so it works whatever
/// language the system runs in. Measured on macOS 26: Fill sits at the top level of
/// the Window menu and Return to Previous Size sits inside its Move & Resize
/// submenu, so the search recurses instead of following a fixed path.
///
/// There is deliberately no title-based fallback. An app that lacks macOS's real
/// tiling items almost never has anything genuinely equivalent to fall back to under
/// an English title, but "Fill" in particular is a common command name in paint, 3D
/// and video apps — a title match would happily bind to a document-modifying command
/// in a completely unrelated menu and Task 8 would press it as though it were window
/// tiling. Apps where the shortcut search finds nothing fall through to Task 8's
/// direct resize instead.
public final class MenuItemFinder {

    /// `AXMenuItemCmdModifiers` for the fn+Control shortcuts macOS gives its tiling
    /// commands: fn (16) + NoCommand (8) + Control (4).
    public static let tilingModifiers = 28

    private var cache: [pid_t: [MenuCommand: AXUIElement]] = [:]
    private let lock = NSLock()

    public init() {}

    public func item(_ command: MenuCommand, pid: pid_t) -> AXUIElement? {
        lock.lock()
        let cached = cache[pid]?[command]
        lock.unlock()
        if let cached, AX.isValid(cached) { return cached }

        guard let found = search(command, pid: pid) else { return nil }

        lock.lock()
        cache[pid, default: [:]][command] = found
        lock.unlock()
        return found
    }

    public func forget(pid: pid_t) {
        lock.lock()
        cache[pid] = nil
        lock.unlock()
    }

    private func search(_ command: MenuCommand, pid: pid_t) -> AXUIElement? {
        let application = AXUIElementCreateApplication(pid)
        guard let menuBar = AX.element(application, kAXMenuBarAttribute as String) else { return nil }

        return walk(menuBar, depth: 0, matches: { item in
            guard let cmdChar = AX.string(item, "AXMenuItemCmdChar"),
                  cmdChar.lowercased() == command.cmdChar else { return false }
            return AX.int(item, "AXMenuItemCmdModifiers") == Self.tilingModifiers
        })
    }

    private func walk(_ element: AXUIElement, depth: Int, limit: Int = 5,
                      matches: (AXUIElement) -> Bool) -> AXUIElement? {
        guard depth <= limit else { return nil }
        for child in AX.children(element) {
            if matches(child) { return child }
            if let found = walk(child, depth: depth + 1, limit: limit, matches: matches) { return found }
        }
        return nil
    }
}
