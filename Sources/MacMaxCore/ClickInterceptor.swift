import ApplicationServices
import CoreGraphics
import Foundation

/// Swallows clicks on green buttons and hands them to `WindowFiller`.
///
/// The callback runs on the main run loop. It does exactly one Accessibility hit test
/// and then returns; the work itself is handed to the filler's own queue. Anything
/// slower than that inside the callback shows up as a sticky mouse.
public final class ClickInterceptor {

    private let filler: WindowFiller
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    /// The click we swallowed the mouse-down of, waiting for its mouse-up.
    private var armed: (hit: GreenButtonHit, action: ClickAction)?

    public var isEnabled = true

    public init(filler: WindowFiller) {
        self.filler = filler
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
            guard isEnabled, let hit = GreenButtonHitTest.hit(at: event.location) else {
                return Unmanaged.passUnretained(event)
            }
            let action = ClickPolicy.action(subrole: hit.subrole, flags: event.flags, enabled: isEnabled)
            guard action != .passThrough else { return Unmanaged.passUnretained(event) }
            armed = (hit, action)
            return nil

        case .leftMouseUp:
            guard let click = armed else { return Unmanaged.passUnretained(event) }
            armed = nil
            // Press on the button, release somewhere else, nothing happens — the way
            // a real button behaves.
            if let buttonFrame = AX.frame(click.hit.button), buttonFrame.contains(event.location) {
                filler.perform(click.action, on: click.hit)
            }
            // The mouse-down was swallowed, so the app must not see a lone mouse-up.
            return nil

        default:
            return Unmanaged.passUnretained(event)
        }
    }
}
