import ApplicationServices
import CoreGraphics
import Foundation

/// A hashable handle on a window.
///
/// `AXUIElement` is a Core Foundation type: `CFEqual` and `CFHash` identify the same
/// window across independent lookups, through the button-to-parent path, and across
/// moves and resizes. That is what makes it usable as a `FrameStore` key.
public struct AXWindowKey: Hashable {
    public let element: AXUIElement

    public init(_ element: AXUIElement) { self.element = element }

    public static func == (lhs: AXWindowKey, rhs: AXWindowKey) -> Bool {
        CFEqual(lhs.element, rhs.element)
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(CFHash(element))
    }
}

public enum AX {

    /// A process-wide ceiling on how long any Accessibility call may block.
    ///
    /// This is deliberately global rather than per-element. The hit test runs inside
    /// the event tap callback, so an unresponsive app must never stall it. A menu
    /// walk that times out merely falls back to a direct resize, which is a fine
    /// outcome; a stalled mouse is not.
    public static let messagingTimeout: Float = 0.1

    public static func configureMessagingTimeout() {
        AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), messagingTimeout)
    }

    public static func copyAttribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }

    public static func string(_ element: AXUIElement, _ name: String) -> String? {
        copyAttribute(element, name) as? String
    }

    public static func int(_ element: AXUIElement, _ name: String) -> Int? {
        copyAttribute(element, name) as? Int
    }

    public static func bool(_ element: AXUIElement, _ name: String) -> Bool? {
        copyAttribute(element, name) as? Bool
    }

    public static func element(_ element: AXUIElement, _ name: String) -> AXUIElement? {
        guard let value = copyAttribute(element, name),
              CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    public static func children(_ element: AXUIElement) -> [AXUIElement] {
        (copyAttribute(element, kAXChildrenAttribute as String) as? [AXUIElement]) ?? []
    }

    public static func pid(of element: AXUIElement) -> pid_t? {
        var pid: pid_t = 0
        guard AXUIElementGetPid(element, &pid) == .success else { return nil }
        return pid
    }

    public static func frame(_ element: AXUIElement) -> CGRect? {
        guard let positionValue = copyAttribute(element, kAXPositionAttribute as String),
              let sizeValue = copyAttribute(element, kAXSizeAttribute as String),
              CFGetTypeID(positionValue) == AXValueGetTypeID(),
              CFGetTypeID(sizeValue) == AXValueGetTypeID() else { return nil }
        var origin = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(positionValue as! AXValue, .cgPoint, &origin),
              AXValueGetValue(sizeValue as! AXValue, .cgSize, &size) else { return nil }
        return CGRect(origin: origin, size: size)
    }

    /// Sets size, then position, then size again. Applications that constrain their
    /// window mid-resize otherwise settle on the wrong final frame.
    @discardableResult
    public static func setFrame(_ element: AXUIElement, _ rect: CGRect) -> Bool {
        var size = rect.size
        var origin = rect.origin
        guard let sizeValue = AXValueCreate(.cgSize, &size),
              let positionValue = AXValueCreate(.cgPoint, &origin) else { return false }
        AXUIElementSetAttributeValue(element, kAXSizeAttribute as CFString, sizeValue)
        AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, positionValue)
        AXUIElementSetAttributeValue(element, kAXSizeAttribute as CFString, sizeValue)
        return true
    }

    @discardableResult
    public static func press(_ element: AXUIElement) -> Bool {
        AXUIElementPerformAction(element, kAXPressAction as CFString) == .success
    }

    @discardableResult
    public static func raise(_ window: AXUIElement) -> Bool {
        AXUIElementPerformAction(window, kAXRaiseAction as CFString) == .success
    }

    public static func isEnabled(_ element: AXUIElement) -> Bool {
        bool(element, kAXEnabledAttribute as String) ?? false
    }

    public static func isValid(_ element: AXUIElement) -> Bool {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &value) != .invalidUIElement
    }

    public static func isFullScreen(_ window: AXUIElement) -> Bool {
        bool(window, "AXFullScreen") ?? false
    }

    @discardableResult
    public static func setFullScreen(_ window: AXUIElement, _ on: Bool) -> Bool {
        AXUIElementSetAttributeValue(window, "AXFullScreen" as CFString, on as CFBoolean) == .success
    }

    /// Reads a window's frame once it stops changing.
    ///
    /// Both native Fill and a direct resize animate, so reading the frame straight
    /// after the action returns the old one. Two identical reads a beat apart mean
    /// the animation has finished. Never call this from the event tap callback.
    public static func settledFrame(of window: AXUIElement, timeout: TimeInterval = 0.5) -> CGRect? {
        let deadline = Date().addingTimeInterval(timeout)
        var last = frame(window)
        while Date() < deadline {
            Thread.sleep(forTimeInterval: 0.04)
            let now = frame(window)
            if now == last { return now }
            last = now
        }
        return last
    }

    /// Waits for a window's frame to move away from `baseline`, then for it to stop
    /// changing, and returns where it came to rest.
    ///
    /// Returns nil when it never moved at all, which is how a caller distinguishes
    /// "the action did not take effect" from "it took effect and landed somewhere".
    /// The plain `settledFrame(of:timeout:)` cannot make that distinction: it samples
    /// twice 40ms apart and will call an animation that has not started yet "settled"
    /// at its pre-action frame. Never call this from the event tap callback.
    public static func settledFrame(of window: AXUIElement, changedFrom baseline: CGRect,
                                    startTimeout: TimeInterval = 1.0) -> CGRect? {
        let deadline = Date().addingTimeInterval(startTimeout)
        while Date() < deadline {
            if let current = frame(window), current != baseline {
                return settledFrame(of: window)
            }
            Thread.sleep(forTimeInterval: 0.03)
        }
        return nil
    }
}
