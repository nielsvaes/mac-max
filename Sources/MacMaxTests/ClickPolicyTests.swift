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

    h.test("couldAct passes exactly the modifier combinations that have a mapping") {
        h.expect(ClickPolicy.couldAct(flags: []), "a plain click could act")
        h.expect(ClickPolicy.couldAct(flags: [.maskAlternate]), "Option+click could act")
        h.expect(!ClickPolicy.couldAct(flags: [.maskCommand]), "Command+click could not act")
        h.expect(!ClickPolicy.couldAct(flags: [.maskControl]), "Control+click could not act")
        h.expect(!ClickPolicy.couldAct(flags: [.maskShift]), "Shift+click could not act")
        h.expect(!ClickPolicy.couldAct(flags: [.maskAlternate, .maskShift]), "Option+Shift+click could not act")
    }

    h.test("couldAct ignores the ride-along bits, so a real event is not screened out") {
        h.expect(ClickPolicy.couldAct(flags: [.maskAlphaShift, .maskNonCoalesced, .maskNumericPad]),
                 "caps lock, non-coalesced and numeric pad alone still could act")
        h.expect(ClickPolicy.couldAct(flags: [.maskAlternate, .maskNonCoalesced]),
                 "Option plus a ride-along bit still could act")
    }

    h.test("screening on modifiers alone is safe for the zoom-only green button as well") {
        let combinations: [CGEventFlags] = [[], [.maskAlternate], [.maskCommand], [.maskAlternate, .maskShift]]
        for flags in combinations {
            let acts = ClickPolicy.action(subrole: GreenButton.zoomSubrole, flags: flags, enabled: true) != .passThrough
            h.expectEqual(ClickPolicy.couldAct(flags: flags), acts)
        }
    }

    h.test("isGreenButton recognises both green button subroles and nothing else") {
        h.expect(GreenButton.isGreenButton(subrole: GreenButton.fullScreenSubrole), "fullscreen button is green")
        h.expect(GreenButton.isGreenButton(subrole: GreenButton.zoomSubrole), "zoom button is green")
        h.expect(!GreenButton.isGreenButton(subrole: "AXMinimizeButton"), "minimize button is not green")
        h.expect(!GreenButton.isGreenButton(subrole: nil), "nil is not green")
    }
}
