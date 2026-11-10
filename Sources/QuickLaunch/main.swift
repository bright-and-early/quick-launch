import AppKit
import Carbon
import QuickLaunchCore

if CommandLine.arguments.contains("--inventory") || CommandLine.arguments.contains("--benchmark") {
    let start = DispatchTime.now().uptimeNanoseconds
    let applications = ApplicationIndex.scan()
    let scanMS = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
    if CommandLine.arguments.contains("--inventory") {
        let rows = applications.map { ["name": $0.name, "path": $0.url.path] }
        let data = try JSONSerialization.data(withJSONObject: rows, options: [.prettyPrinted, .sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    } else {
        let queries = ["s", "sa", "saf", "term", "am", "gchr", "code", "cal", "zzzz"]
        var latencies: [Double] = []
        var resultCount = 0
        for _ in 0..<250 {
            for query in queries {
                let start = DispatchTime.now().uptimeNanoseconds
                resultCount += AppSearch.results(for: query, in: applications).count
                latencies.append(Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000)
            }
        }
        latencies.sort()
        print("Applications: \(applications.count)")
        print(String(format: "Index scan: %.2f ms", scanMS))
        print(String(format: "Search median: %.3f ms; p95: %.3f ms; max: %.3f ms (%d queries)", latencies[latencies.count/2], latencies[Int(Double(latencies.count)*0.95)], latencies.last!, latencies.count))
        print("Result checksum: \(resultCount)")
    }
    exit(0)
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var launcher: LauncherController!
    private var item: NSStatusItem!
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?

    func applicationDidFinishLaunching(_ notification: Notification) {
        if NSRunningApplication.runningApplications(withBundleIdentifier: "dev.woozy.quick-launch").filter({ $0.processIdentifier != getpid() }).count > 0 {
            NSApp.terminate(nil)
            return
        }
        // Standard responder actions keep Command-A/C/V/X functional in the
        // search field even though this app has no Dock window or document menu.
        let mainMenu = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit Quick Launch", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        mainMenu.addItem(appItem)
        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        for (title, action, key) in [
            ("Cut", #selector(NSText.cut(_:)), "x"),
            ("Copy", #selector(NSText.copy(_:)), "c"),
            ("Paste", #selector(NSText.paste(_:)), "v"),
            ("Select All", #selector(NSText.selectAll(_:)), "a")
        ] { editMenu.addItem(withTitle: title, action: action, keyEquivalent: key) }
        editItem.submenu = editMenu
        mainMenu.addItem(editItem)
        NSApp.mainMenu = mainMenu
        launcher = LauncherController()
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: "Quick Launch")
        let menu = NSMenu()
        menu.addItem(withTitle: "Open Quick Launch", action: #selector(showLauncher), keyEquivalent: "")
        menu.addItem(withTitle: "Refresh Applications", action: #selector(refresh), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Quick Launch", action: #selector(quit), keyEquivalent: "q")
        for entry in menu.items { entry.target = self }
        item.menu = menu
        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let context = Unmanaged.passUnretained(self).toOpaque()
        let installStatus = InstallEventHandler(GetApplicationEventTarget(), { _, _, context in
            guard let context = context else { return OSStatus(eventNotHandledErr) }
            let delegate = Unmanaged<AppDelegate>.fromOpaque(context).takeUnretainedValue()
            delegate.launcher.toggle()
            return noErr
        }, 1, &type, context, &handler)
        let id = EventHotKeyID(signature: 0x514C4348, id: 1)
        let status = RegisterEventHotKey(UInt32(kVK_Space), UInt32(cmdKey), id, GetApplicationEventTarget(), 0, &hotKey)
        NSLog("Quick Launch: event handler=%d; Command-Space registration=%d", installStatus, status)
        if status != noErr || installStatus != noErr {
            DispatchQueue.main.async {
                let alert = NSAlert()
                alert.messageText = "Command–Space is already in use"
                alert.informativeText = "Turn off the Spotlight Command–Space shortcut in System Settings → Keyboard → Keyboard Shortcuts → Spotlight, then quit and reopen Quick Launch. You can open the launcher from its menu bar icon. (Registration: \(status), handler: \(installStatus))"
                alert.addButton(withTitle: "OK")
                NSApp.activate(ignoringOtherApps: true)
                alert.runModal()
            }
        } else {
            launcher.toggle()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { launcher.toggle() }
        return true
    }
    func applicationWillTerminate(_ notification: Notification) {
        if let hotKey = hotKey { UnregisterEventHotKey(hotKey) }
        if let handler = handler { RemoveEventHandler(handler) }
    }
    @objc private func showLauncher() { if !launcher.panel.isVisible { launcher.toggle() } }
    @objc private func refresh() { launcher.refreshIndex(force: true) }
    @objc private func quit() { NSApp.terminate(nil) }
}

let application = NSApplication.shared
let delegate = AppDelegate()
application.setActivationPolicy(.accessory)
application.delegate = delegate
application.run()
