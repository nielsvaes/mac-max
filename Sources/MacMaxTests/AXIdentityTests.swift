import ApplicationServices
import MacMaxCore

func runAXIdentityTests(_ h: Harness) {
    h.test("two handles on the same system-wide element are one key") {
        let first = AXWindowKey(AXUIElementCreateSystemWide())
        let second = AXWindowKey(AXUIElementCreateSystemWide())
        h.expectEqual(first, second)
        h.expectEqual(first.hashValue, second.hashValue)
        h.expectEqual(Set([first, second]).count, 1)
    }

    h.test("two handles on the same process are one key") {
        let first = AXWindowKey(AXUIElementCreateApplication(1))
        let second = AXWindowKey(AXUIElementCreateApplication(1))
        h.expectEqual(first, second)
        h.expectEqual(Set([first, second]).count, 1)
    }

    h.test("handles on different processes are different keys") {
        let first = AXWindowKey(AXUIElementCreateApplication(1))
        let second = AXWindowKey(AXUIElementCreateApplication(2))
        h.expect(first != second, "different pids must not collide")
        h.expectEqual(Set([first, second]).count, 2)
    }

    h.test("a process handle is not the system-wide handle") {
        h.expect(AXWindowKey(AXUIElementCreateApplication(1)) != AXWindowKey(AXUIElementCreateSystemWide()),
                 "an app element must not equal the system-wide element")
    }
}
