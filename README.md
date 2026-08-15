# Mac Max

Clicking the green stoplight button on a macOS window normally enters native
fullscreen: a new Space, the menu bar and Dock hidden, every other window cut off.
Mac Max is a small background utility that changes what a plain click on that button
does — fills the window over its current display instead — and moves native
fullscreen to `Option`+click.

| Click | Effect |
|---|---|
| Plain click on the green button | Fill the window on its current display, or restore it to its previous size and position if Mac Max already filled it |
| `Option`+click on the green button | Toggle native fullscreen — the button's old behaviour |
| Anything else — `Command`/`Control`/`Shift`+click, hovering, dragging off before releasing, or a click that isn't on the green button at all | Passed through unchanged |

It has no windows, no Dock icon and no application menu. It lives entirely as a
menu-bar status item (a window icon) with three items: **Enabled**, **Launch at
Login**, and **Quit Mac Max**.

## Requirements

- macOS 14 or later (`LSMinimumSystemVersion` in the bundle's `Info.plist`).
- Built and tested on macOS 26.6.1 (Tahoe), Apple Silicon, using only the Swift
  toolchain and Command Line Tools — no Xcode project.

## Installing

```
make install
```

This runs `swift build -c release`, assembles `build/Mac Max.app` via
`scripts/bundle.sh`, replaces any existing copy in `/Applications`, and opens it.

If you'd rather build and run without touching `/Applications`, use `make run`
instead — it bundles and opens `build/Mac Max.app` in place.

## Granting Accessibility permission

Mac Max needs Accessibility permission to see clicks and read window geometry. On
first launch it requests it automatically; until it's granted, the menu bar item
shows **Waiting for Accessibility permission…** and **Open Privacy & Security…**, and
no clicks are intercepted (the app is inert, not just quiet, while untrusted).

Click **Open Privacy & Security…**, or go to **System Settings → Privacy & Security →
Accessibility** yourself, and turn on the switch for **Mac Max**. The app polls once a
second and the menu updates to **Enabled** as soon as permission lands — no relaunch
needed.

### Keeping permission across rebuilds

macOS ties an Accessibility grant to the app's code signature, not just its bundle
identifier. `scripts/bundle.sh` signs with a code-signing identity named `Mac Max Dev`
if one exists on this machine, and falls back to an ad-hoc signature otherwise. An
ad-hoc signature is regenerated on every build, so macOS treats each rebuild as a
different app and makes you re-grant Accessibility every time.

To avoid that, create a stable local identity once:

1. Open **Keychain Access**.
2. **Keychain Access → Certificate Assistant → Create a Certificate…**
3. Name it exactly `Mac Max Dev`.
4. Set **Identity Type** to **Self Signed Root**, **Certificate Type** to **Code
   Signing**.
5. Create it.

`scripts/bundle.sh` picks up `Mac Max Dev` automatically on the next build and
reports `built build/Mac Max.app, signed with "Mac Max Dev"` instead of the ad-hoc
warning. You can also point it at a different identity without editing the script, by
setting `MACMAX_SIGN_IDENTITY`:

```
MACMAX_SIGN_IDENTITY="Some Other Identity" make bundle
```

### If permission gets confused

If Accessibility permission is stuck — Mac Max shows as trusted in System Settings
but clicks aren't intercepted, or the reverse — reset just this app's entry and
re-grant it from a clean state:

```
make reset-permission
```

This runs `tccutil reset Accessibility com.nielsvaes.MacMax`. It only touches Mac
Max's own TCC entry; nothing else on the machine is affected.

## Enabling/disabling and Launch at Login

The **Enabled** checkbox in the menu bar toggles interception on and off instantly,
without quitting the app — useful for the "does this feel wrong, is it Mac Max"
question. Its state is remembered across launches.

**Launch at Login** registers the app with `SMAppService` so it starts automatically
next time you log in; it's off by default.

## Debugging with the probe

`MacMaxProbe` is a separate command-line target — not part of the shipped app — that
exercises the same `MacMaxCore` code the app uses, for debugging without the event
tap in the way:

```
make probe ARGS=<command>
```

or the equivalent `swift run MacMaxProbe <command>` directly. The commands actually
implemented (`Sources/MacMaxProbe/main.swift`):

| Command | What it does |
|---|---|
| `screens` | Prints every screen's frame and visible frame, in both Cocoa and Accessibility coordinates. |
| `menu <app name>` | Dumps that app's whole menu bar tree (role, title, keyboard shortcut, enabled state), depth-limited. |
| `window <app name>` | Prints that app's focused window's title, frame, fullscreen state, and the frame of every traffic-light-shaped button on it. |
| `watch` | Every 500ms, prints whatever Accessibility element sits under the cursor. Runs forever — `Ctrl-C` to stop. |
| `hit` | Polls the cursor every 300ms and reports when it's over a green button. Also runs forever — `Ctrl-C` to stop. |
| `hit <x> <y>` | One-shot: hit-tests a single Accessibility-space point and exits immediately. This is the one to use for scripted checks. |
| `find <app name>` | Locates that app's `Fill` and `Return to Previous Size` menu items via their keyboard shortcut, independent of display language, and prints what it found. |
| `fill <app name>` | **Not read-only.** Fills the app's focused window, waits a second, then restores it — two real `WindowFiller` actions against a live window. Useful for confirming fill/restore works for a given app, but it will move whatever window is currently focused there. |

`ARGS` is passed through as-is, so multi-word arguments need their own quoting, e.g.
`make probe ARGS='find "Windows App"'`.

## Testing

```
make test
```

runs the unit suite (`swift run MacMaxTests`) — pure logic only: coordinate
conversion, the click-to-action policy, the fill/restore frame store, and
Accessibility-element identity. None of it touches a real click, a real window, or
Accessibility permission.

Everything downstream of an actual click — the event tap, the hit test against a
live button, menu presses, and the visible on-screen result — cannot be unit tested
and is covered instead by
[`docs/manual-test-matrix.md`](docs/manual-test-matrix.md), a 21-row matrix meant to
be run by hand with the built app running and enabled. As of this writing most of
that matrix is still pending a human pass — see that document for exactly what has
and hasn't been exercised.
