import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

/// Fills, restores and fullscreens windows.
///
/// Everything here runs on `queue`, never on the main thread and never inside the
/// event tap callback: pressing a menu item and waiting for the window to settle
/// takes a few hundred milliseconds, which must not touch the input path.
public final class WindowFiller {

    private let queue = DispatchQueue(label: "com.nielsvaes.MacMax.filler")
    private let store = FrameStore<AXWindowKey>()
    private let menus = MenuItemFinder()

    public init() {}

    public func perform(_ action: ClickAction, on hit: GreenButtonHit) {
        queue.async { [weak self] in self?.performSynchronously(action, on: hit) }
    }

    public func performSynchronously(_ action: ClickAction, on hit: GreenButtonHit) {
        switch action {
        case .passThrough:
            return
        case .toggleFullScreen:
            toggleFullScreen(hit)
        case .fillOrRestore:
            fillOrRestore(hit)
        }
        store.prune { AX.isValid($0.element) }
    }

    public func forgetApplication(pid: pid_t) {
        menus.forget(pid: pid)
    }

    // MARK: - Actions

    private func toggleFullScreen(_ hit: GreenButtonHit) {
        focus(hit)
        let wasFullScreen = AX.isFullScreen(hit.window)
        if !AX.setFullScreen(hit.window, !wasFullScreen) {
            // Windows that do not expose AXFullScreen still respond to their own
            // green button, whose default action is the one we want here.
            AX.press(hit.button)
        }
        // A fullscreen window's frame has nothing to do with what we recorded.
        store.forget(AXWindowKey(hit.window))
    }

    private func fillOrRestore(_ hit: GreenButtonHit) {
        guard let current = AX.frame(hit.window) else { return }
        focus(hit)

        let key = AXWindowKey(hit.window)
        if let record = store.restorable(key, currentFrame: current) {
            restore(hit, to: record)
            store.forget(key)
        } else {
            fill(hit, from: current)
        }
    }

    private func fill(_ hit: GreenButtonHit, from previous: CGRect) {
        var method = FillMethod.directResize

        if let item = menus.item(.fill, pid: hit.pid), AX.isEnabled(item), AX.press(item),
           let settled = AX.settledFrame(of: hit.window), settled != previous {
            method = .nativeTiling
        } else if let target = fillTarget(for: previous) {
            AX.setFrame(hit.window, target)
        } else {
            return
        }

        guard let applied = AX.settledFrame(of: hit.window) else { return }
        store.record(AXWindowKey(hit.window), previousFrame: previous, appliedFrame: applied, method: method)
    }

    private func restore(_ hit: GreenButtonHit, to record: FillRecord) {
        if record.method == .nativeTiling,
           let item = menus.item(.returnToPreviousSize, pid: hit.pid),
           AX.isEnabled(item), AX.press(item),
           let settled = AX.settledFrame(of: hit.window), settled != record.appliedFrame {
            return
        }
        AX.setFrame(hit.window, record.previousFrame)
    }

    // MARK: - Helpers

    /// Brings the window forward. Both tiling menu items are disabled unless their
    /// application is frontmost with the target window focused, and swallowing the
    /// click means macOS has not activated anything on our behalf.
    private func focus(_ hit: GreenButtonHit) {
        AX.raise(hit.window)
        let pid = hit.pid
        DispatchQueue.main.async {
            NSRunningApplication(processIdentifier: pid)?.activate()
        }
        Thread.sleep(forTimeInterval: 0.12)
    }

    private func fillTarget(for windowFrame: CGRect) -> CGRect? {
        let snapshot = ScreenProvider.shared.snapshot
        return AXGeometry.fillTarget(for: windowFrame,
                                     screenFrames: snapshot.frames,
                                     visibleFrames: snapshot.visibleFrames)
    }
}
