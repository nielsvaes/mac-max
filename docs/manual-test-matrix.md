# Mac Max — manual verification matrix

**macOS version:** 26.6.1 (build 25G76)
**Date written:** 2026-08-15
**Owner verification began:** 2026-08-16, against an installed, `Mac Max Dev`-signed build

## Status of this matrix

**The core interaction is confirmed by real clicks.** The owner has run rows 1, 2 and 4
against a live installed build: a plain click fills, a second click restores, and
`Option`+click enters native fullscreen. That is the first evidence in this project
that the session event tap actually receives and acts on genuine mouse clicks —
everything recorded as *automated* below was driven by calling into the code directly.

The remaining rows are still unrun. Most of them require a human physically clicking,
Option-clicking or Command-clicking a real traffic-light button, which cannot be done
programmatically from the build environment
(a TCC grant needs SIP disabled to script, and a synthetic `CGEvent` post is not the
same code path as a real click arriving at the session event tap). The project owner
is expected to run this matrix by hand and fill in the remaining **Result** cells.

Where a row's underlying mechanism was exercised directly during implementation —
calling `WindowFiller`, `GreenButtonHitTest` or `FrameStore` in isolation, or a pure
logic unit test — that is recorded below as **automated**, with the Result pre-filled
and a citation to the exact evidence. Automated evidence is explicitly **not** the
same claim as "a real click does this": Task 9's `ClickInterceptor` — the code that
actually sits on the session event tap and swallows/forwards real mouse clicks — has
never been exercised by an actual click in any task's evidence. Rows without direct
automated evidence are marked **pending — needs a human click**, with Result left
blank. Nothing in this document should be read as "all green" until the owner has
worked through it.

### Operational note from first install (2026-08-16)

Granting Accessibility permission failed on the first attempt in a way worth
recording, because the symptom is misleading: System Settings showed **Mac Max** as
enabled while the app still reported "Waiting for Accessibility permission…", and
relaunching re-prompted. The cause was a stale TCC entry — with no signing identity
present, `scripts/bundle.sh` had fallen back to an ad-hoc signature, and TCC pins
ad-hoc grants to the exact binary hash. An earlier automated verification build had
been granted and then denied under the same bundle identifier, and `make install`
replaces the bundle at a path that already had an entry; either invalidates the pin
while leaving the row visible in the UI.

Toggling the checkbox off and on does **not** clear it. The fix is
`make reset-permission` (or removing the row with **−**) followed by a fresh grant.
The durable fix is a stable signing identity: once a self-signed `Mac Max Dev` code
signing certificate existed and was trusted for code signing, the grant survived
rebuilds. This is the failure the README's signing-identity section exists to prevent.

## The matrix

| # | Scenario | Expected | Result | Covered by |
|---|---|---|---|---|
| 1 | Click green on a Finder window | Fills the display, stays in the current Space, menu bar and Dock still visible | **PASS — real click, owner-verified 2026-08-16** | Owner clicked the green button on a live window with an installed, `Mac Max Dev`-signed build and reported it fills. This is the first end-to-end confirmation that the whole chain runs on a genuine click: event tap → `GreenButtonHitTest` → `ClickPolicy` → `WindowFiller` → macOS Fill. Supporting mechanism evidence: `WindowFiller.performSynchronously(.fillOrRestore, on:)` was driven directly (not via a click) against a live Finder window in Task 8 and landed exactly on the screen's AX visible frame (`filled: (-0.0, 30.0, 1408.0, 851.0)` vs. `ax visibleFrame: (0.0, 30.0, 1408.0, 851.0)` — task-8-report.md, Check 1). That proves the fill *mechanism* is correct; it does not prove a real click reaches it, since `ClickInterceptor` (Task 9) has never been driven by an actual mouse click. "Stays in the current Space" and "menu bar/Dock still visible" were never measured by any task. |
| 2 | Click green again | Returns to the previous size and position | **PASS — real click, owner-verified 2026-08-16** | Owner confirmed a second click restores the window. Together with row 1 this closes the fill/restore toggle, the feature's central promise, under real clicks. Supporting mechanism evidence, Task 8: driven directly, the restore matched `before` exactly or within ~1pt on every edge across several runs (task-8-report.md, Checks 1–2 and the round-1 fix's re-verification). The click path is untested. |
| 3 | Fill, drag the window somewhere else, click green | Fills fresh rather than snapping back to the old frame | PASS — automated, not click-driven | Task 8, "Check 3 — moved-window case": within one `WindowFiller`/`FrameStore` instance, the window was moved via `osascript` between an internal fill call and an internal restore call on a live Finder window. Output: `before: (420.0, 160.0, 700.0, 550.0)`, `filled: (0.0, 30.0, 1408.0, 851.0)`, `restored: (0.0, 30.0, 1408.0, 851.0)` — it filled fresh again rather than snapping back to `before`, proving `FrameStore.restorable`'s mismatch detection genuinely drops a stale record. Reconfirmed under a real pumped run loop with a temporary, uncommitted harness reproduced in full in the same report. This establishes the underlying mechanism; it was never triggered by an actual fill→drag→click sequence. |
| 4 | `Option`+click green | Enters native fullscreen on a new Space | **PASS — real click, owner-verified 2026-08-16** | Owner confirmed `Option`+click enters native fullscreen, exercising `WindowFiller.toggleFullScreen`'s live `AX.setFullScreen` call for the first time. Note the owner reported entering fullscreen; leaving it again is row 5 and is still unrun. Supporting logic evidence: `Sources/MacMaxTests/ClickPolicyTests.swift` ("Option+click toggles fullscreen") unit-tests only that `ClickPolicy.action` *decides* on `.toggleFullScreen` when the Option flag is held — pure logic, no Accessibility involved. No task ever exercised `WindowFiller.toggleFullScreen`'s actual `AX.setFullScreen`/`AX.press` call, or observed a real Space transition. |
| 5 | `Option`+click green again while fullscreen | Leaves fullscreen | | Pending — needs a human click. Same gap as row 4: nothing in any report exercises `toggleFullScreen` live, in either direction. |
| 6 | Click green while fullscreen | Leaves fullscreen (the click passes through) | | Pending — needs a human click. No automated evidence at all. Worth flagging plainly: `ClickPolicy.action` does not special-case an already-fullscreen window — a plain click on a green button subrole always maps to `.fillOrRestore`. Whether this row's expected passthrough happens depends on `GreenButtonHitTest` failing to find a hittable green button while the window is in native fullscreen (a different Space), which no task has characterized. This is not asserted to be a defect — it is genuinely unverified, and the mechanism that would make the expected result happen is not obvious from reading the code alone. |
| 7 | `Command`+click green | macOS's default behaviour, unchanged | | Pending — needs a human click. `ClickPolicyTests.swift` ("Command+click passes through") confirms the decision logic in isolation (`.maskCommand` held → `.passThrough`), which is the entirety of what Mac Max's own code does for this case — once `.passThrough` is chosen, `ClickInterceptor` forwards the event untouched and macOS handles the rest itself. Higher confidence than most pending rows below, since there is little left for Mac Max to get wrong, but never observed via an actual Command-click through the event tap. |
| 8 | Click red, click yellow | Close and minimise, unaffected | PASS — automated, not click-driven | Task 6, checks 2–3: `make probe ARGS="hit <x> <y>"` at the live screen coordinates of a real Finder window's `AXCloseButton` (513, 223) and `AXMinimizeButton` (536, 223) both returned `no green button at (...)`, confirming `GreenButtonHitTest` discriminates by subrole and would decline to intercept either click — `ClickInterceptor` would pass both through untouched, taking no action of its own. This is a direct hit-test call at those coordinates, not a real click delivered through the event tap, and Finder's actual close/minimize behaviour was not separately observed (it does not need to be: once the hit test declines, Mac Max never calls anything). |
| 9 | Press on green, drag off, release | Nothing happens | | Pending — needs a human click. `ClickInterceptor.handle(type:event:)`'s mouse-up branch structurally implements exactly this (`buttonFrame.contains(event.location)` gates the call to `filler.perform`, per `Sources/MacMaxCore/ClickInterceptor.swift`), reviewed by reading the code in Task 9's self-review, but never exercised with an actual press/drag-off/release sequence. |
| 10 | Hover green without clicking | The system tiling menu still appears | | Pending — needs a human click. `ClickInterceptor.start()`'s tap mask is `(1 << leftMouseDown) \| (1 << leftMouseUp)` only — no hover/mouse-moved events are tapped at all, so macOS's own hover-menu handling is structurally untouched by Mac Max. That is a fact read from the source, not a live observation; nobody has hovered a green button with Mac Max running. |
| 11 | Click a tiling option inside that hover menu | It works normally | | Pending — needs a human click. Same reasoning as row 10 — the hover menu and its items are entirely outside the event tap's mask — but this has not been observed live. |
| 12 | Click green on a **background** window | That window comes forward and fills | PASS — automated, not click-driven | Task 8, round-1 fix, "Decisive test that the root-cause race is actually fixed": with a different app ("Claude") genuinely frontmost and Finder not reactivated by anything except `WindowFiller` itself, calling `fillOrRestore` directly under a real, pumped run loop flipped `NSWorkspace.shared.frontmostApplication` from Claude to Finder (via `focus()`'s own `.activate()` request) and then filled Finder to the exact AX visible frame. This proves `WindowFiller.focus()` genuinely brings a backgrounded app's window forward and fills it, using a temporary, uncommitted run-loop harness (full source reproduced in task-8-report.md) — but it was driven directly against a live app pair, not by clicking a green button on an actual background window. |
| 13 | Repeat rows 1–2 in Safari, Terminal, System Settings, Preview | Same behaviour | | Pending — needs a human click, for all four apps. Task 7 confirmed Safari's native `Fill`/`Return to Previous Size` menu items are found (`enabled: false` while backgrounded, as expected for an AppKit app) — but no fill/restore cycle was ever run against Safari, Terminal, System Settings or Preview in any task; Task 8's live fill/restore evidence covers Finder only. |
| 14 | Repeat rows 1–2 in an Electron app such as VS Code | Fills — via direct resize if it has no Fill menu item | | Pending — needs a human click. Task 7 confirmed VS Code (Code) exposes a native `Fill` menu item (found via shortcut match, `enabled: true`) and a `Return to Previous Size` item — meaning VS Code likely takes the native-tiling path rather than needing the direct-resize fallback this row describes — but no fill was ever actually driven against VS Code in any task; Task 8's live fill/restore evidence covers Finder only. |
| 15 | Click green on a window with a size limit, such as About This Mac | Grows as far as it can, or nothing happens; no crash, no stuck click | | Pending — needs a human click. `WindowFiller.fill(_:from:focused:)` has an explicit guard for exactly this case: a window whose settled frame still matches `previous` within tolerance — the code comment names "a non-resizable window such as About This Mac" — is not recorded, avoiding a dead second click. This path has never been exercised against a real size-limited window in any task. |
| 16 | Move a window to a second display and click green | Fills that display, not the primary | | Pending — needs a human click. This development machine has a single physical display: every task's `make probe ARGS=screens` output shows exactly one `screen 0` entry (e.g. Task 5: `primary height: 881.0`, one screen listed). Multi-monitor behaviour could not be exercised by any task in this environment, let alone by a real click. |
| 17 | Untick **Enabled**, click green | Default fullscreen behaviour returns immediately | | Pending — needs a human click. `ClickPolicyTests.swift` ("everything passes through while disabled") confirms `ClickPolicy.action` returns `.passThrough` unconditionally when `enabled: false`. Task 10's self-review confirmed, by reading the code, that `AppDelegate.toggleEnabled()` flips `interceptor.isEnabled` and persists it to `UserDefaults`. Neither the menu checkbox nor the resulting live behaviour was exercised in any task. |
| 18 | Tick **Enabled** again | Filling works again | | Pending — needs a human click. Same evidence and same gap as row 17. |
| 19 | Tick **Launch at Login**, log out and back in | Mac Max starts by itself | | Pending — needs a human click. No evidence in any report. Task 10 explicitly did not touch Launch at Login during its verification ("I did not touch Launch at Login anywhere in this session"). |
| 20 | Click rapidly on green ten times | No stuck clicks, no runaway windows, the mouse stays responsive | | Pending — needs a human click. No evidence in any report. |
| 21 | Fill a window, close it, open twenty more windows | No memory growth or stale-frame weirdness — the store prunes | PASS — automated (pure logic), not click-driven | `Sources/MacMaxTests/FrameStoreTests.swift` unit-tests both halves of this claim directly: "the store evicts the oldest record once it is full" (default `capacity: 64`, oldest-first eviction) and "prune drops records whose windows are gone" (`WindowFiller.performSynchronously` calls `store.prune { AX.isValid($0.element) }` after every action, and `AX.isValid` does a live `AXUIElementCopyAttributeValue` round trip that correctly reports `.invalidUIElement` once a window/app is gone). Both pass as part of `make test`'s 53/53 (confirmed while writing this document). This proves the store cannot grow past 64 records and does discard dead entries on the next action — it does not simulate 20 real windows opening and closing live, nor observe actual process memory. |

## Summary

- **Confirmed by real clicks (owner, 2026-08-16):** rows 1, 2, 4 — 3 of 21.
- **Automated (evidence gathered, not click-driven):** rows 3, 8, 12, 21 — 4 of 21.
- **Pending — needs a human click:** rows 5, 6, 7, 9, 10, 11, 13, 14, 15, 16, 17, 18, 19, 20 — 14 of 21.

The three confirmed rows are the ones the feature is actually for. The highest-value
remaining rows are 6 (green while already fullscreen — reworked in the final fix wave
and never exercised), 13–14 (other apps, particularly one where
`make probe ARGS="find <name>"` reports NOT FOUND, which is the direct-resize
fallback), and a row not in this table at all: a plain click on a **background,
non-key** window, which exercises an `AX.isEnabled` guard added in the final pass.

Anything that fails when the owner runs the pending rows becomes a fix; re-run the
affected row (and any row whose evidence the fix could have changed) after fixing, and
update this table in place.
