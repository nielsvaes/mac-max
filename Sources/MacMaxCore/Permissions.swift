import ApplicationServices

public enum Permissions {
    private static var promptKey: String {
        kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
    }

    /// Whether Accessibility permission has been granted. Never prompts.
    public static var isTrusted: Bool {
        AXIsProcessTrustedWithOptions([promptKey: false] as CFDictionary)
    }

    /// Asks macOS to show the Accessibility permission prompt.
    public static func requestAccess() {
        _ = AXIsProcessTrustedWithOptions([promptKey: true] as CFDictionary)
    }
}
