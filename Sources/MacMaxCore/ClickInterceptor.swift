import ApplicationServices
import CoreGraphics
import Foundation

/// Swallows clicks on green buttons and hands them to `WindowFiller`.
///
/// The callback runs on the main run loop, so what it does there is what the mouse
/// waits for. Every Accessibility call it makes is bounded by `AX.messagingTimeout`,
/// and the count is kept small: a mouse-down carrying modifiers Mac Max does not
/// claim is dismissed from the event alone, at no Accessibility cost at all. A
/// mouse-down that survives that costs the hit test — the element at the point, its
/// subrole and a one-level walk to its window, at most five round trips — plus a read
/// of the button's frame, two more. The mouse-up costs nothing: it reuses that frame,
/// and the work itself goes to the filler's own queue. Anything slower than that
/// inside the callback shows up as a sticky mouse.
public final class ClickInterceptor {

    private let filler: WindowFiller
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    /// The click we swallowed the mouse-down of, waiting for its mouse-up, together
    /// with where the button was when we swallowed it.
    private var armed: (hit: GreenButtonHit, action: ClickAction, buttonFrame: CGRect)?

    public var isEnabled = true

    public init(filler: WindowFiller) {
        self.filler = filler
    }

    /// The tap holds an unretained pointer to `self` and is kept alive by the run
    /// loop, not by Swift's ARC, so it outlives this object unless torn down here —
    /// without this, releasing a running interceptor would leave the callback holding
    /// a dangling pointer for the next click.
    deinit {
        stop()
    }

    public var isRunning: Bool { tap != nil }

    /// Returns false when the tap cannot be created, which in practice always means
    /// Accessibility permission has not been granted.
    @discardableResult
    public func start() -> Bool {
        guard tap == nil else { return true }

        let mask = (1 << CGEventType.leftMouseDown.rawValue) | (1 << CGEventType.leftMouseUp.rawValue)
        let callback: CGEventTapCallBack = { _, type, event, refcon in
            guard let refcon else { return Unmanaged.passUnretained(event) }
            let interceptor = Unmanaged<ClickInterceptor>.fromOpaque(refcon).takeUnretainedValue()
            return interceptor.handle(type: type, event: event)
        }

        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap,
                                          place: .headInsertEventTap,
                                          options: .defaultTap,
                                          eventsOfInterest: CGEventMask(mask),
                                          callback: callback,
                                          userInfo: Unmanaged.passUnretained(self).toOpaque())
        else { return false }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        self.tap = tap
        self.runLoopSource = source
        return true
    }

    public func stop() {
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        tap = nil
        runLoopSource = nil
        armed = nil
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            // macOS switches the tap off if it ever runs long. Switch it back on.
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)

        case .leftMouseDown:
            armed = nil
            // Modifiers first: they are already on the event, whereas the subrole
            // costs round trips into an application that may be hung. A click whose
            // modifiers have no mapping cannot become anything but a pass-through, so
            // it never reaches the hit test.
            guard isEnabled, ClickPolicy.couldAct(flags: event.flags),
                  let hit = GreenButtonHitTest.hit(at: event.location) else {
                return Unmanaged.passUnretained(event)
            }
            let action = ClickPolicy.action(subrole: hit.subrole, flags: event.flags, enabled: isEnabled)
            // The frame is read now rather than on the up: swallowing the down means
            // nothing can move the window before the up arrives, and the up then costs
            // no Accessibility call at all. Without it there is no way to tell a
            // release on the button from one off it, so the click is left alone.
            guard action != .passThrough, let buttonFrame = AX.frame(hit.button) else {
                return Unmanaged.passUnretained(event)
            }
            armed = (hit, action, buttonFrame)
            return nil

        case .leftMouseUp:
            guard let click = armed else { return Unmanaged.passUnretained(event) }
            armed = nil
            // Press on the button, release somewhere else, nothing happens — the way
            // a real button behaves.
            if click.buttonFrame.contains(event.location) {
                filler.perform(click.action, on: click.hit)
            }
            // The mouse-down was swallowed, so the app must not see a lone mouse-up.
            return nil

        default:
            return Unmanaged.passUnretained(event)
        }
    }
}
