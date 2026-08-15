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

default:
    usage()
}
