import ApplicationServices
import CoreGraphics

public struct GreenButtonHit {
    public let button: AXUIElement
    public let window: AXUIElement
    public let pid: pid_t
    public let subrole: String

    public init(button: AXUIElement, window: AXUIElement, pid: pid_t, subrole: String) {
        self.button = button
        self.window = window
        self.pid = pid
        self.subrole = subrole
    }
}

public enum GreenButtonHitTest {

    private static let systemWide = AXUIElementCreateSystemWide()

    /// The green button at `point`, if there is one.
    ///
    /// `point` is in Accessibility coordinates, which is also what `CGEvent.location`
    /// gives, so an event's location can be passed straight in. Runs inside the event
    /// tap callback, so it does nothing beyond three attribute reads.
    public static func hit(at point: CGPoint) -> GreenButtonHit? {
        var element: AXUIElement?
        guard AXUIElementCopyElementAtPosition(systemWide, Float(point.x), Float(point.y), &element) == .success,
              let button = element else { return nil }

        guard let subrole = AX.string(button, kAXSubroleAttribute as String),
              GreenButton.isGreenButton(subrole: subrole) else { return nil }

        guard let pid = AX.pid(of: button),
              let window = enclosingWindow(of: button) else { return nil }

        return GreenButtonHit(button: button, window: window, pid: pid, subrole: subrole)
    }

    /// Walks up from the button to its window. Measured on macOS 26 the window is the
    /// button's immediate parent; the extra depth is slack for non-standard windows.
    static func enclosingWindow(of element: AXUIElement, maxDepth: Int = 5) -> AXUIElement? {
        var current = element
        for _ in 0..<maxDepth {
            if AX.string(current, kAXRoleAttribute as String) == (kAXWindowRole as String) { return current }
            guard let parent = AX.element(current, kAXParentAttribute as String) else { return nil }
            current = parent
        }
        return nil
    }
}
