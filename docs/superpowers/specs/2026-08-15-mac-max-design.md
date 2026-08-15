# Mac Max — Design

**Date:** 2026-08-15
**Status:** Approved
**Target:** macOS 26 (Tahoe), Apple Silicon, Swift 6.3, Command Line Tools only (no Xcode)

## Problem

Clicking the green stoplight button enters native fullscreen: the window moves to a
new Space, the menu bar and Dock hide, and the app is cut off from every other
window. What is wanted almost every time is **Fill** — the window grows to cover the
display it is already on, in the Space it is already in, with the menu bar and Dock
still there. macOS exposes Fill via `fn`+`Control`+`F` and via the green button's
hover menu, but never via a plain click.

Mac Max makes a plain click on the green button do Fill, and moves native fullscreen
to `Option`+click. It does nothing else.

## Behavior

| Input | Result |
|---|---|
| Click green button | Fill the window on its current display |
| Click green button on an already-filled window | Restore its previous size and position |
| `Option`+click green button | Toggle native fullscreen |
| `Command` / `Control` / `Shift` + click green button | Passed through unchanged |
| Hover green button | Untouched — the system tiling menu still appears |
| Click inside that hover menu | Passed through (hit-tests as a menu item, not a button) |
| Click green button on a fullscreen window | Passed through, so it exits fullscreen as usual |
| Click anywhere that is not a green button | Passed through — the app is invisible |

`Option`+click currently means Zoom. Mac Max takes that combination over; Zoom
remains reachable from the Window menu.

## Approach

Three ways to intercept the click were considered.

**Dylib injection / button swizzling.** Replace the button's action inside each
process. Gives a genuinely native button, but requires SIP disabled and code
injected into every application. Rejected.

**React after the fact.** Let the click enter fullscreen, observe the transition
with an `AXObserver`, then exit fullscreen and fill. Needs no event tap, but the
Space animation plays in and out on every click. Rejected.

**CGEventTap + Accessibility API.** Tap left mouse down/up session-wide, ask the
Accessibility API what sits under the cursor, and swallow the click when it is a
green button. Chosen. One permission (Accessibility) covers both the modifying
event tap and the window manipulation.

## Architecture

```
main.swift ──▶ AppDelegate
                 ├─▶ Permissions          AX trust prompt, poll until granted
                 ├─▶ StatusItem           menu bar: Enabled / Launch at Login / Quit
                 └─▶ ClickInterceptor     CGEventTap lifecycle
                        │
                        ├─ ZoomButtonHitTest   point → (subrole, window, pid)
                        └─ WindowFiller        fill / restore / fullscreen
                             ├─ MenuItemFinder   Fill & Return to Previous Size
                             ├─ FrameStore       remembered pre-fill frames
                             └─ AXGeometry       coordinate conversion, screen picking
```

Each unit is replaceable in isolation: `AXGeometry` and `FrameStore` are pure value
logic with no Accessibility dependency, `ZoomButtonHitTest` answers one question
about a point, `MenuItemFinder` answers one question about a process, and
`WindowFiller` is the only place that mutates a window.

## Click path

```
leftMouseDown
  ├─ interception disabled?                            → pass through
  ├─ modifiers other than Option present?               → pass through
  ├─ element under point is not a green button?         → pass through
  └─ arm (window, optionDown) and SWALLOW

leftMouseUp
  └─ SWALLOW, then dispatch asynchronously:
       activate the owning app, raise the window
       optionDown → toggle native fullscreen
       else       → fill or restore
```

Only the hit test runs inside the tap callback. `AXUIElementSetMessagingTimeout` is
set to 50 ms, so an unresponsive application cannot stall the mouse — the hit test
fails, the click passes through, and the window enters fullscreen as it would have
without Mac Max. All window mutation happens off the callback, so menu-walking
latency never reaches the input system.

Both the down and the up are swallowed. An application that receives a lone mouse-up
should not act on it. If the button is pressed and released elsewhere, nothing
happens, matching how a real button behaves.

The tap is created with `.cgSessionEventTap` / `.headInsertEventTap` /
`.defaultTap`. `tapDisabledByTimeout` and `tapDisabledByUserInput` re-enable the tap
from the callback.

## Hit test

`AXUIElementCopyElementAtPosition` on the system-wide element, using the event's
location directly — `CGEvent.location` and Accessibility coordinates share the same
space (origin at the top-left of the primary display, y increasing downward).

A green button is an element whose `AXSubrole` is `AXFullScreenButton` (windows that
support fullscreen) or `AXZoomButton` (windows that do not). The owning window is
found by walking `AXParent` until an element with role `AXWindow` appears, to a depth
of five. The owning process comes from `AXUIElementGetPid`.

## Fill and restore

```
fill(window):
    previous ← current frame
    item ← Fill menu item for this pid
    if item exists and pressing it changes the frame:
        method ← .nativeTiling
    else:
        set size, position, size to the visible frame of the window's screen
        method ← .directResize
    store (previous, resulting frame, method)

restore(window):
    method is .nativeTiling and a Return to Previous Size item exists:
        press it
    otherwise:
        set size, position, size back to the stored previous frame
```

Size is set, then position, then size again. Applications that constrain their
window during a resize otherwise land on the wrong final frame.

**Deciding between fill and restore.** Not by measuring the window against the
screen — native Fill may inset the window when "tiled windows have margins" is on,
which makes a geometric test unreliable. Instead `FrameStore` records the frame Mac
Max produced. A click restores only when the window still sits within 2 pt of that
frame. Move or resize the window yourself and the next click fills fresh.

**Window identity.** `AXUIElement` is a Core Foundation type supporting `CFEqual` and
`CFHash`, so windows are keyed by a `Hashable` wrapper over those. Entries whose
element has become invalid are pruned lazily on access, and the store is capped.

**Locating the Fill menu item without depending on language.** The menu bar of the
target process is walked recursively for an item whose `AXMenuItemCmdChar` is `f`
with the Control modifier — the `fn`+`Control`+`F` binding, whatever the system
language calls the item. A title match against a small table is tried next, and
direct resize catches everything else. The result is cached per pid and dropped when
the process terminates, so only the first click on a given application pays the walk.

**Multiple displays.** The window fills whichever screen its frame overlaps most.

## Coordinates

Cocoa places the origin at the bottom-left of the primary screen with y increasing
upward; Accessibility places it at the top-left with y increasing downward. The
conversion in both directions is

```
axY = primaryScreenHeight - (cocoaY + height)
```

`AXGeometry` takes screen frames as plain `CGRect` values rather than reading
`NSScreen` itself, which keeps the conversion and the screen-picking logic testable
without a display attached.

## Application shell

An `LSUIElement` background application with a status bar item offering **Enabled**,
**Launch at Login**, and **Quit**. Enabled state persists in `UserDefaults`; launch at
login uses `SMAppService.mainApp`.

Accessibility permission is requested with `AXIsProcessTrustedWithOptions` and polled
once a second until granted, at which point the tap starts. The menu shows the
permission state while it is missing.

## Packaging

SwiftPM executable, since no Xcode is installed. `scripts/bundle.sh` assembles
`build/Mac Max.app` around the release binary with an `Info.plist` and an ad-hoc
signature. Bundle identifier `com.nielsvaes.MacMax`.

Accessibility permission is bound to the code signature, and an ad-hoc signature
changes on every rebuild, so macOS will periodically require re-granting permission
after a rebuild. `make reset-permission` runs `tccutil reset Accessibility
com.nielsvaes.MacMax` for when the permission state becomes inconsistent.

## Testing

Unit tests cover the logic that holds no Accessibility dependency:

- coordinate conversion, round-tripping between Cocoa and Accessibility space
- screen picking by largest overlap, including a window straddling two displays
- the fill/restore state machine: fill records, second click restores, a moved
  window fills fresh, restore after direct resize versus after native tiling
- modifier-to-action mapping, including pass-through for unhandled modifiers
- the "still where we put it" tolerance at and beyond its 2 pt boundary

Event taps, Accessibility hit tests, and menu pressing need a real logged-in session
and granted permission, so they are covered by a `--debug` mode that logs what each
click hit (subrole, application, window title, chosen method) and a written manual
matrix: Finder, Safari, Terminal, System Settings, an Electron application, a
non-resizable window, a second display, an already-fullscreen window, and a
background window.

## Out of scope

Title-bar double-click, keyboard shortcuts, per-application rules, window snapping to
halves or quarters, and any preferences window. The utility does one thing.
