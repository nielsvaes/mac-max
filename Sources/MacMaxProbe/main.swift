import AppKit
import ApplicationServices
import MacMaxCore

// The probe is a development tool, not part of the shipped app. It needs a generous
// timeout because it walks whole menu trees.
AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), 2.0)

func usage() -> Never {
    print("""
    usage: swift run MacMaxProbe <command>

      screens              screen frames in Cocoa and Accessibility coordinates
      menu <app name>      the app's Window menu, with shortcuts and enabled state
      window <app name>    the app's focused window: frame and traffic-light subroles
      watch                every 500ms, print what sits under the cursor
      hit                  poll the cursor and report green-button hits
      hit <x> <y>          one-shot hit test at that Accessibility-space point
      find <app name>      locate the Fill and Return to Previous Size commands
      fill <app name>      fill the app's focused window, then restore it
    """)
    exit(1)
}

func app(named name: String) -> NSRunningApplication {
    guard let match = NSWorkspace.shared.runningApplications.first(where: { $0.localizedName == name }) else {
        print("no running app named \(name)")
        exit(1)
    }
    return match
}

func describe(_ element: AXUIElement, depth: Int) {
    let indent = String(repeating: "  ", count: depth)
    let role = AX.string(element, kAXRoleAttribute as String) ?? "?"
    let title = AX.string(element, kAXTitleAttribute as String) ?? ""
    var extra = ""
    if let cmdChar = AX.string(element, "AXMenuItemCmdChar"), !cmdChar.isEmpty {
        extra += "  [cmdChar=\(cmdChar) mods=\(AX.int(element, "AXMenuItemCmdModifiers") ?? -1)]"
    }
    if !AX.isEnabled(element) { extra += "  (disabled)" }
    print("\(indent)\(role) \"\(title)\"\(extra)")
    guard depth < 4 else { return }
    for child in AX.children(element) { describe(child, depth: depth + 1) }
}

let arguments = Array(CommandLine.arguments.dropFirst())
guard let command = arguments.first else { usage() }

switch command {
case "screens":
    ScreenProvider.shared.refresh()
    let snapshot = ScreenProvider.shared.snapshot
    print("primary height:", snapshot.primaryHeight)
    for (index, screen) in NSScreen.screens.enumerated() {
        print("screen \(index)")
        print("  cocoa frame:        ", screen.frame)
        print("  cocoa visibleFrame: ", screen.visibleFrame)
        print("  ax frame:           ", snapshot.frames[index])
        print("  ax visibleFrame:    ", snapshot.visibleFrames[index])
    }

case "menu":
    guard arguments.count > 1 else { usage() }
    let target = app(named: arguments[1])
    let axApp = AXUIElementCreateApplication(target.processIdentifier)
    guard let menuBar = AX.element(axApp, kAXMenuBarAttribute as String) else {
        print("no menu bar"); exit(1)
    }
    for menu in AX.children(menuBar) { describe(menu, depth: 0) }

case "window":
    guard arguments.count > 1 else { usage() }
    let target = app(named: arguments[1])
    let axApp = AXUIElementCreateApplication(target.processIdentifier)
    guard let window = AX.element(axApp, kAXFocusedWindowAttribute as String) else {
        print("no focused window"); exit(1)
    }
    print("title:     ", AX.string(window, kAXTitleAttribute as String) ?? "?")
    print("frame:     ", AX.frame(window).map(String.init(describing:)) ?? "?")
    print("fullScreen:", AX.isFullScreen(window))
    for child in AX.children(window) {
        guard let subrole = AX.string(child, kAXSubroleAttribute as String),
              subrole.hasSuffix("Button") else { continue }
        print("  \(subrole)  frame: \(AX.frame(child).map(String.init(describing:)) ?? "?")")
    }

case "watch":
    let systemWide = AXUIElementCreateSystemWide()
    print("move the cursor over a green button; ctrl-c to stop")
    while true {
        let location = CGEvent(source: nil)?.location ?? .zero
        var element: AXUIElement?
        if AXUIElementCopyElementAtPosition(systemWide, Float(location.x), Float(location.y), &element) == .success,
           let element {
            let subrole = AX.string(element, kAXSubroleAttribute as String) ?? "-"
            let role = AX.string(element, kAXRoleAttribute as String) ?? "-"
            let pid = AX.pid(of: element).map(String.init) ?? "?"
            print(String(format: "%.0f,%.0f", location.x, location.y), role, subrole, "pid:\(pid)")
        }
        Thread.sleep(forTimeInterval: 0.5)
    }

case "hit":
    if arguments.count > 1 {
        guard arguments.count >= 3, let x = Double(arguments[1]), let y = Double(arguments[2]) else {
            print("usage: swift run MacMaxProbe hit <x> <y>"); exit(1)
        }
        let point = CGPoint(x: x, y: y)
        if let found = GreenButtonHitTest.hit(at: point) {
            let title = AX.string(found.window, kAXTitleAttribute as String) ?? "?"
            print("HIT  subrole=\(found.subrole)  pid=\(found.pid)  window=\"\(title)\"  " +
                  "buttonFrame=\(AX.frame(found.button).map(String.init(describing:)) ?? "?")")
        } else {
            print("no green button at \(point)")
        }
    } else {
        print("hover a green button; ctrl-c to stop")
        while true {
            let location = CGEvent(source: nil)?.location ?? .zero
            if let found = GreenButtonHitTest.hit(at: location) {
                let title = AX.string(found.window, kAXTitleAttribute as String) ?? "?"
                print("HIT  subrole=\(found.subrole)  pid=\(found.pid)  window=\"\(title)\"  " +
                      "buttonFrame=\(AX.frame(found.button).map(String.init(describing:)) ?? "?")")
            }
            Thread.sleep(forTimeInterval: 0.3)
        }
    }

case "find":
    guard arguments.count > 1 else { usage() }
    let target = app(named: arguments[1])
    let finder = MenuItemFinder()
    for command in [MenuCommand.fill, .returnToPreviousSize] {
        if let item = finder.item(command, pid: target.processIdentifier) {
            print("\(command): found \"\(AX.string(item, kAXTitleAttribute as String) ?? "?")\"",
                  "enabled: \(AX.isEnabled(item))")
        } else {
            print("\(command): NOT FOUND")
        }
    }

case "fill":
    guard arguments.count > 1 else { usage() }
    let target = app(named: arguments[1])
    let axApp = AXUIElementCreateApplication(target.processIdentifier)
    guard let window = AX.element(axApp, kAXFocusedWindowAttribute as String),
          let button = AX.children(window).first(where: {
              GreenButton.isGreenButton(subrole: AX.string($0, kAXSubroleAttribute as String))
          }),
          let subrole = AX.string(button, kAXSubroleAttribute as String) else {
        print("no focused window with a green button"); exit(1)
    }
    ScreenProvider.shared.refresh()
    let hit = GreenButtonHit(button: button, window: window,
                             pid: target.processIdentifier, subrole: subrole)
    let filler = WindowFiller()
    print("before:  ", AX.frame(window)!)
    filler.performSynchronously(.fillOrRestore, on: hit)
    print("filled:  ", AX.frame(window)!)
    Thread.sleep(forTimeInterval: 1.0)
    filler.performSynchronously(.fillOrRestore, on: hit)
    print("restored:", AX.frame(window)!)

default:
    usage()
}
