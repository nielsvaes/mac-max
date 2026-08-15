import CoreGraphics
import MacMaxCore

func runAXGeometryTests(_ h: Harness) {
    // The numbers here were measured on a real display: a 1408x881 screen whose
    // Cocoa visibleFrame is (0, 0, 1408, 851), which macOS's own Fill turns into
    // the AX frame (0, 30, 1408, 851).
    h.test("flip converts a measured visibleFrame to the measured AX fill frame") {
        let cocoaVisible = CGRect(x: 0, y: 0, width: 1408, height: 851)
        let ax = AXGeometry.flip(cocoaVisible, primaryScreenHeight: 881)
        h.expectEqual(ax, CGRect(x: 0, y: 30, width: 1408, height: 851))
    }

    h.test("flip is its own inverse") {
        let original = CGRect(x: 120, y: 64, width: 800, height: 600)
        let there = AXGeometry.flip(original, primaryScreenHeight: 881)
        let back = AXGeometry.flip(there, primaryScreenHeight: 881)
        h.expectEqual(back, original)
    }

    h.test("flip handles a screen positioned above the primary, where Cocoa y exceeds the primary height") {
        let above = CGRect(x: 0, y: 881, width: 1000, height: 500)
        let ax = AXGeometry.flip(above, primaryScreenHeight: 881)
        h.expectEqual(ax, CGRect(x: 0, y: -500, width: 1000, height: 500))
    }

    let left = CGRect(x: 0, y: 0, width: 1000, height: 800)
    let right = CGRect(x: 1000, y: 0, width: 1000, height: 800)

    h.test("screenIndex picks the only screen") {
        h.expectEqual(AXGeometry.screenIndex(for: CGRect(x: 10, y: 10, width: 100, height: 100),
                                             screenFrames: [left]), 0)
    }

    h.test("screenIndex picks the screen with the larger overlap") {
        // 300pt on the left screen, 700pt on the right
        let straddling = CGRect(x: 700, y: 100, width: 1000, height: 400)
        h.expectEqual(AXGeometry.screenIndex(for: straddling, screenFrames: [left, right]), 1)
    }

    h.test("screenIndex falls back to the nearest screen when nothing overlaps") {
        let offscreen = CGRect(x: 5000, y: 100, width: 100, height: 100)
        h.expectEqual(AXGeometry.screenIndex(for: offscreen, screenFrames: [left, right]), 1)
    }

    h.test("screenIndex returns nil with no screens") {
        h.expectEqual(AXGeometry.screenIndex(for: left, screenFrames: []), nil)
    }

    let reference = CGRect(x: 0, y: 30, width: 1408, height: 851)

    h.test("matches accepts an identical frame") {
        h.expect(AXGeometry.matches(reference, reference, tolerance: 2), "identical frames must match")
    }

    h.test("matches accepts drift exactly at the tolerance") {
        let drifted = CGRect(x: 2, y: 32, width: 1408, height: 851)
        h.expect(AXGeometry.matches(drifted, reference, tolerance: 2), "2pt drift is within a 2pt tolerance")
    }

    h.test("matches rejects drift beyond the tolerance") {
        let drifted = CGRect(x: 3, y: 30, width: 1408, height: 851)
        h.expect(!AXGeometry.matches(drifted, reference, tolerance: 2), "3pt drift exceeds a 2pt tolerance")
    }

    h.test("matches rejects a size change even when the origin is unmoved") {
        let resized = CGRect(x: 0, y: 30, width: 1000, height: 851)
        h.expect(!AXGeometry.matches(resized, reference, tolerance: 2), "a narrower window must not match")
    }

    h.test("fillTarget returns the visible frame of the window's screen") {
        let visibleLeft = CGRect(x: 0, y: 30, width: 1000, height: 770)
        let visibleRight = CGRect(x: 1000, y: 30, width: 1000, height: 770)
        let window = CGRect(x: 1100, y: 100, width: 400, height: 300)
        h.expectEqual(AXGeometry.fillTarget(for: window,
                                            screenFrames: [left, right],
                                            visibleFrames: [visibleLeft, visibleRight]),
                      visibleRight)
    }

    h.test("fillTarget returns nil when screen and visible frame counts disagree") {
        h.expectEqual(AXGeometry.fillTarget(for: left, screenFrames: [left, right], visibleFrames: [left]), nil)
    }
}
