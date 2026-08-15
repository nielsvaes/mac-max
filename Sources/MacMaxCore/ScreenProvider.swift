import AppKit
import CoreGraphics
import Foundation

/// Screen geometry in Accessibility coordinates, already converted.
public struct ScreenSnapshot: Sendable {
    public let primaryHeight: CGFloat
    public let frames: [CGRect]
    public let visibleFrames: [CGRect]

    public static let empty = ScreenSnapshot(primaryHeight: 0, frames: [], visibleFrames: [])
}

/// Caches screen geometry so the window-filling code, which runs off the main
/// thread, never has to touch `NSScreen` itself.
public final class ScreenProvider {
    public static let shared = ScreenProvider()

    private var cached = ScreenSnapshot.empty
    private let lock = NSLock()

    private init() {}

    public var snapshot: ScreenSnapshot {
        lock.lock(); defer { lock.unlock() }
        return cached
    }

    /// Must be called on the main thread.
    public func refresh() {
        let screens = NSScreen.screens
        let primaryHeight = screens.first?.frame.height ?? 0
        let snapshot = ScreenSnapshot(
            primaryHeight: primaryHeight,
            frames: screens.map { AXGeometry.flip($0.frame, primaryScreenHeight: primaryHeight) },
            visibleFrames: screens.map { AXGeometry.flip($0.visibleFrame, primaryScreenHeight: primaryHeight) }
        )
        lock.lock()
        cached = snapshot
        lock.unlock()
    }

    /// Must be called on the main thread.
    public func startObserving() {
        refresh()
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refresh()
        }
    }
}
