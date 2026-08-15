import CoreGraphics

/// What a click on the green button should do.
public enum ClickAction: Equatable, Sendable {
    /// Let the click reach the application untouched.
    case passThrough
    /// Fill the window, or restore it if Mac Max filled it last.
    case fillOrRestore
    /// Enter or leave native fullscreen.
    case toggleFullScreen
}

public enum GreenButton {
    /// The green button on a window that can enter fullscreen.
    public static let fullScreenSubrole = "AXFullScreenButton"
    /// The green button on a window that cannot, which zooms instead.
    public static let zoomSubrole = "AXZoomButton"

    public static func isGreenButton(subrole: String?) -> Bool {
        subrole == fullScreenSubrole || subrole == zoomSubrole
    }
}

public enum ClickPolicy {

    /// The modifiers that change what a click means. Caps lock, the numeric pad bit
    /// and the non-coalesced bit ride along on ordinary events and must be ignored,
    /// or every real click would look modified.
    static let considered: CGEventFlags = [
        .maskCommand, .maskControl, .maskShift, .maskAlternate, .maskSecondaryFn,
    ]

    public static func action(subrole: String?, flags: CGEventFlags, enabled: Bool) -> ClickAction {
        guard enabled, GreenButton.isGreenButton(subrole: subrole) else { return .passThrough }

        let held = flags.intersection(considered)
        if held.isEmpty { return .fillOrRestore }
        if held == .maskAlternate { return .toggleFullScreen }
        return .passThrough
    }
}
