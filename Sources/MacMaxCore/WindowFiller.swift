import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

/// Fills, restores and fullscreens windows.
///
/// `perform(_:on:)` is the normal entry point: it hands off to `queue` and returns
/// immediately, so it is safe to call from anywhere, including the event tap
/// callback. `performSynchronously(_:on:)` and `forgetApplication` instead run on
/// whatever thread calls them — the probe calls `performSynchronously` directly from
/// `main` for that reason. `performSynchronously` presses menu items and waits for
/// windows to settle, which can take up to a second or so; it must never be called
/// from the main thread or from inside the event tap callback.
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
        guard AX.isEnabled(hit.button) else { return }
        focus(hit)
        // Whether the attribute exists at all is the question, not what it says: a
        // window that does not expose AXFullScreen cannot be fullscreened by setting
        // it, and only that window needs the button pressed instead. Falling back on
        // a failed *set* would be wrong — a set that reports failure at the 100ms
        // messaging timeout may still have been delivered, and an app mid-fullscreen
        // transition is exactly the app that runs long, so the press would toggle
        // straight back.
        if let isFullScreen = AX.bool(hit.window, "AXFullScreen") {
            AX.setFullScreen(hit.window, !isFullScreen)
        } else {
            AX.press(hit.button)
        }
        // A fullscreen window's frame has nothing to do with what we recorded.
        store.forget(AXWindowKey(hit.window))
    }

    private func fillOrRestore(_ hit: GreenButtonHit) {
        // A disabled green button — a window with a modal sheet attached — still
        // hit-tests, so the click has already been swallowed by the time we get here.
        // Doing nothing is what a disabled button does; acting would move a window
        // that macOS itself would have left alone.
        guard AX.isEnabled(hit.button) else { return }

        // Fill does not exist in fullscreen, so a fullscreen window gets the outcome
        // the spec promises — it leaves fullscreen — delivered here rather than by
        // passing the click through. Checked on this queue and not in the tap: the
        // input path must not pay an Accessibility round trip on every green-button
        // click for a case this rare. The store is deliberately untouched, because a
        // fullscreen frame is not a size to restore to; recording one would hand a
        // later restore the whole display, menu bar included. Setting the attribute
        // names `hit.window` outright, so unlike a menu item it needs no activation
        // first, and skipping the focus poll keeps the dead time between the click
        // and the exit down to the transition itself.
        if AX.isFullScreen(hit.window) {
            AX.setFullScreen(hit.window, false)
            return
        }

        guard let current = AX.frame(hit.window) else { return }
        let focused = focus(hit)

        let key = AXWindowKey(hit.window)
        if let record = store.restorable(key, currentFrame: current) {
            // Only drop the record once the window has actually been put back.
            // Forgetting it on a failed restore would leave the window filled with
            // no way back to `previousFrame`, and the next click would record the
            // filled frame itself as "previous".
            if restore(hit, to: record, focused: focused) {
                store.forget(key)
            }
        } else {
            fill(hit, from: current, focused: focused)
        }
    }

    private func fill(_ hit: GreenButtonHit, from previous: CGRect, focused: Bool) {
        if let applied = nativeFill(hit, from: previous, focused: focused) {
            store.record(AXWindowKey(hit.window), previousFrame: previous, appliedFrame: applied, method: .nativeTiling)
            return
        }

        guard let target = fillTarget(for: previous) else { return }
        AX.setFrame(hit.window, target)
        // Waiting for the frame to leave `previous`, exactly as the native path does.
        // The plain two-sample settle would read the pre-move frame twice on an app
        // that animates or defers the resize, and the window would end up filled but
        // unrecorded — so the next click would fill again instead of restoring.
        guard let applied = AX.settledFrame(of: hit.window, changedFrom: previous),
              // A window that did not actually move — a non-resizable window such as
              // About This Mac — is not worth remembering. Recording it anyway would
              // cost the user a second dead click undoing a fill that never happened.
              !AXGeometry.matches(applied, previous, tolerance: store.tolerance) else { return }
        store.record(AXWindowKey(hit.window), previousFrame: previous, appliedFrame: applied, method: .directResize)
    }

    /// Attempts macOS's own Fill command and reports where the window landed, or nil
    /// if it did not actually work. Only tried once focus is confirmed: the item is
    /// disabled otherwise, and pressing it acts on the app's focused window rather
    /// than on `hit.window` specifically, so an unconfirmed focus could fill some
    /// other window of the same app instead of this one.
    private func nativeFill(_ hit: GreenButtonHit, from previous: CGRect, focused: Bool) -> CGRect? {
        guard focused, let item = menus.item(.fill, pid: hit.pid), AX.isEnabled(item) else { return nil }
        AX.press(item)
        // The press's own return value is not trustworthy here: a call that reports
        // failure at the 100ms messaging timeout may still have been delivered. The
        // frame moving is what decides whether this actually did anything.
        guard let settled = AX.settledFrame(of: hit.window, changedFrom: previous),
              !AXGeometry.matches(settled, previous, tolerance: store.tolerance) else { return nil }
        return settled
    }

    /// Undoes a fill, reporting whether the window actually ended up back at
    /// `record.previousFrame`.
    ///
    /// Neither path can answer that on its own. `AX.setFrame` reports only whether it
    /// could build the values to send, never whether the window took them. And macOS
    /// keeps its own untile anchor, which can differ from the frame we recorded, so
    /// Return to Previous Size moving the window is not the same as it moving the
    /// window back. Whichever path ran, the frame is therefore verified against
    /// `previousFrame` and corrected once directly if it is not there. Only a true
    /// return lets the caller drop the record, which is what keeps a genuinely failed
    /// restore retryable instead of losing the pre-fill geometry for good.
    private func restore(_ hit: GreenButtonHit, to record: FillRecord, focused: Bool) -> Bool {
        if !nativeRestore(hit, to: record, focused: focused) {
            AX.setFrame(hit.window, record.previousFrame)
        }
        if hasSettled(hit.window, at: record.previousFrame) { return true }
        AX.setFrame(hit.window, record.previousFrame)
        return hasSettled(hit.window, at: record.previousFrame)
    }

    /// Attempts Return to Previous Size and reports whether it moved the window at
    /// all. Only tried once focus is confirmed and the record says a native fill is
    /// what put the window there — pressing it on a directly-resized window would do
    /// nothing useful even if it succeeded. Where the window landed is `restore`'s
    /// question, not this one's.
    private func nativeRestore(_ hit: GreenButtonHit, to record: FillRecord, focused: Bool) -> Bool {
        guard focused, record.method == .nativeTiling,
              let item = menus.item(.returnToPreviousSize, pid: hit.pid), AX.isEnabled(item) else { return false }
        AX.press(item)
        guard let settled = AX.settledFrame(of: hit.window, changedFrom: record.appliedFrame),
              !AXGeometry.matches(settled, record.appliedFrame, tolerance: store.tolerance) else { return false }
        return true
    }

    /// Whether the window has come to rest at `target`. A window whose frame cannot be
    /// read at all counts as not there, which is the safe answer: it keeps the record
    /// until `prune` decides the window is gone.
    private func hasSettled(_ window: AXUIElement, at target: CGRect) -> Bool {
        guard let frame = AX.settledFrame(of: window) else { return false }
        return AXGeometry.matches(frame, target, tolerance: store.tolerance)
    }

    // MARK: - Helpers

    /// Requests activation, then polls for it to actually take effect rather than
    /// assuming a fixed delay was enough. `NSRunningApplication.activate()` is
    /// asynchronous, and once the event tap is live on the main run loop (Task 9),
    /// main can still be busy with an AX round-trip when a fixed sleep would have
    /// expired — a race that usually wins, not a barrier.
    ///
    /// Returns true only once the target app reports itself frontmost with
    /// `hit.window` as its focused window, which both tiling menu items require to
    /// be enabled and which is also what keeps a native action aimed at `hit.window`
    /// rather than some other window of the same app.
    @discardableResult
    private func focus(_ hit: GreenButtonHit) -> Bool {
        AX.raise(hit.window)
        let pid = hit.pid
        DispatchQueue.main.async {
            NSRunningApplication(processIdentifier: pid)?.activate()
        }

        let axApp = AXUIElementCreateApplication(pid)
        let deadline = Date().addingTimeInterval(0.5)
        while true {
            if AX.bool(axApp, kAXFrontmostAttribute as String) == true,
               let focusedWindow = AX.element(axApp, kAXFocusedWindowAttribute as String),
               CFEqual(focusedWindow, hit.window) {
                return true
            }
            guard Date() < deadline else { return false }
            Thread.sleep(forTimeInterval: 0.03)
        }
    }

    private func fillTarget(for windowFrame: CGRect) -> CGRect? {
        let snapshot = ScreenProvider.shared.snapshot
        return AXGeometry.fillTarget(for: windowFrame,
                                     screenFrames: snapshot.frames,
                                     visibleFrames: snapshot.visibleFrames)
    }
}
