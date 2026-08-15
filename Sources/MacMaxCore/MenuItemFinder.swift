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

    /// Last-resort English titles, used only when the shortcut match fails.
    var titles: [String] {
        switch self {
        case .fill: return ["Fill"]
        case .returnToPreviousSize: return ["Return to Previous Size"]
        }
    }
}

/// Locates macOS's own window-tiling menu commands inside another application.
///
/// The match is on the keyboard shortcut rather than the title, so it works whatever
/// language the system runs in. Measured on macOS 26: Fill sits at the top level of
/// the Window menu and Return to Previous Size sits inside its Move & Resize
/// submenu, so the search recurses instead of following a fixed path.
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

        if let match = walk(menuBar, depth: 0, matches: { item in
            guard let cmdChar = AX.string(item, "AXMenuItemCmdChar"),
                  cmdChar.lowercased() == command.cmdChar else { return false }
            return AX.int(item, "AXMenuItemCmdModifiers") == Self.tilingModifiers
        }) {
            return match
        }

        return walk(menuBar, depth: 0, matches: { item in
            guard let title = AX.string(item, kAXTitleAttribute as String) else { return false }
            return command.titles.contains(title)
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
