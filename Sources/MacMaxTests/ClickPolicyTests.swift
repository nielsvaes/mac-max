import CoreGraphics
import MacMaxCore

func runClickPolicyTests(_ h: Harness) {
    let green = GreenButton.fullScreenSubrole

    h.test("a plain click on the green button fills") {
        h.expectEqual(ClickPolicy.action(subrole: green, flags: [], enabled: true), .fillOrRestore)
    }

    h.test("a plain click on a zoom-only green button fills") {
        h.expectEqual(ClickPolicy.action(subrole: GreenButton.zoomSubrole, flags: [], enabled: true),
                      .fillOrRestore)
    }

    h.test("Option+click toggles fullscreen") {
        h.expectEqual(ClickPolicy.action(subrole: green, flags: [.maskAlternate], enabled: true),
                      .toggleFullScreen)
    }

    h.test("Command+click passes through") {
        h.expectEqual(ClickPolicy.action(subrole: green, flags: [.maskCommand], enabled: true), .passThrough)
    }

    h.test("Option+Shift+click passes through, because it is not the mapping we claimed") {
        h.expectEqual(ClickPolicy.action(subrole: green, flags: [.maskAlternate, .maskShift], enabled: true),
                      .passThrough)
    }

    h.test("caps lock is ignored, so a click with it on still fills") {
        h.expectEqual(ClickPolicy.action(subrole: green, flags: [.maskAlphaShift], enabled: true),
                      .fillOrRestore)
    }

    h.test("the non-coalesced bit that every real event carries is ignored") {
        h.expectEqual(ClickPolicy.action(subrole: green, flags: [.maskNonCoalesced], enabled: true),
                      .fillOrRestore)
    }

    h.test("the numeric pad bit is ignored") {
        h.expectEqual(ClickPolicy.action(subrole: green, flags: [.maskNumericPad], enabled: true),
                      .fillOrRestore)
    }

    h.test("Option plus the non-coalesced bit still toggles fullscreen") {
        h.expectEqual(ClickPolicy.action(subrole: green, flags: [.maskAlternate, .maskNonCoalesced], enabled: true),
                      .toggleFullScreen)
    }

    h.test("the close button passes through") {
        h.expectEqual(ClickPolicy.action(subrole: "AXCloseButton", flags: [], enabled: true), .passThrough)
    }

    h.test("nothing under the cursor passes through") {
        h.expectEqual(ClickPolicy.action(subrole: nil, flags: [], enabled: true), .passThrough)
    }

    h.test("everything passes through while disabled") {
        h.expectEqual(ClickPolicy.action(subrole: green, flags: [], enabled: false), .passThrough)
        h.expectEqual(ClickPolicy.action(subrole: green, flags: [.maskAlternate], enabled: false), .passThrough)
    }

    h.test("isGreenButton recognises both green button subroles and nothing else") {
        h.expect(GreenButton.isGreenButton(subrole: GreenButton.fullScreenSubrole), "fullscreen button is green")
        h.expect(GreenButton.isGreenButton(subrole: GreenButton.zoomSubrole), "zoom button is green")
        h.expect(!GreenButton.isGreenButton(subrole: "AXMinimizeButton"), "minimize button is not green")
        h.expect(!GreenButton.isGreenButton(subrole: nil), "nil is not green")
    }
}
