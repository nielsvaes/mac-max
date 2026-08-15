import AppKit
import MacMaxCore
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate {

    private let filler = WindowFiller()
    private lazy var interceptor = ClickInterceptor(filler: filler)
    private var statusItem: NSStatusItem?
    private var permissionTimer: Timer?

    private enum Defaults {
        static let enabled = "enabled"
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        UserDefaults.standard.register(defaults: [Defaults.enabled: true])

        AX.configureMessagingTimeout()
        ScreenProvider.shared.startObserving()

        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            else { return }
            self?.filler.forgetApplication(pid: app.processIdentifier)
        }

        setUpStatusItem()
        interceptor.isEnabled = UserDefaults.standard.bool(forKey: Defaults.enabled)
        startInterceptingWhenPermitted()
    }

    func applicationWillTerminate(_ notification: Notification) {
        interceptor.stop()
    }

    // MARK: - Permission

    private func startInterceptingWhenPermitted() {
        if interceptor.start() {
            permissionTimer?.invalidate()
            permissionTimer = nil
            refreshMenu()
            return
        }

        Permissions.requestAccess()
        refreshMenu()
        guard permissionTimer == nil else { return }
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.startInterceptingWhenPermitted()
        }
    }

    // MARK: - Status item

    private func setUpStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(systemSymbolName: "macwindow", accessibilityDescription: "Mac Max")
        item.menu = NSMenu()
        statusItem = item
        refreshMenu()
    }

    private func refreshMenu() {
        guard let menu = statusItem?.menu else { return }
        menu.removeAllItems()

        if !interceptor.isRunning {
            let waiting = NSMenuItem(title: "Waiting for Accessibility permission…", action: nil, keyEquivalent: "")
            waiting.isEnabled = false
            menu.addItem(waiting)
            menu.addItem(NSMenuItem(title: "Open Privacy & Security…",
                                    action: #selector(openPrivacySettings), keyEquivalent: ""))
            menu.addItem(.separator())
        } else {
            let enabled = NSMenuItem(title: "Enabled", action: #selector(toggleEnabled), keyEquivalent: "")
            enabled.state = interceptor.isEnabled ? .on : .off
            menu.addItem(enabled)
        }

        let login = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Mac Max", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        for item in menu.items where item.action != nil && item.target == nil {
            if item.action != #selector(NSApplication.terminate(_:)) { item.target = self }
        }
    }

    @objc private func toggleEnabled() {
        interceptor.isEnabled.toggle()
        UserDefaults.standard.set(interceptor.isEnabled, forKey: Defaults.enabled)
        refreshMenu()
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            NSLog("Mac Max: could not change launch at login: \(error)")
        }
        refreshMenu()
    }

    @objc private func openPrivacySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }
}
