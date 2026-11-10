import AppKit
import Carbon
import QuickLaunchCore
import QuickLaunchUI

if let index = CommandLine.arguments.firstIndex(of: "--spotlight-apply") {
    guard geteuid() == 0, CommandLine.arguments.indices.contains(index + 1),
          let data = Data(base64Encoded: CommandLine.arguments[index + 1]), data.count < 100_000,
          let request = try? JSONDecoder().decode(SpotlightRequest.self, from: data), request.isValid else {
        fputs("Invalid or unprivileged Spotlight request.\n", stderr); exit(1)
    }
    let changes = SpotlightServices.apply(request, run: SystemCommand.launchctl)
    FileHandle.standardOutput.write(try JSONEncoder().encode(changes))
    exit(0)
}
if CommandLine.arguments.contains("--spotlight-status") {
    let inventory = SpotlightServices.discover(uid: getuid(), run: SystemCommand.launchctl)
    FileHandle.standardOutput.write(try JSONEncoder().encode(inventory.services))
    for error in inventory.errors { fputs(error + "\n", stderr) }
    exit(inventory.errors.isEmpty ? 0 : 1)
}

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
        menu.addItem(withTitle: "Enable Window Animations…", action: #selector(enableAnimations), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Quick Launch", action: #selector(quit), keyEquivalent: "q")
        for entry in menu.items { entry.target = self }
        item.menu = menu
        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let context = Unmanaged.passUnretained(self).toOpaque()
        let installStatus = InstallEventHandler(GetApplicationEventTarget(), { _, _, context in
            guard let context = context else { return OSStatus(eventNotHandledErr) }
            let delegate = Unmanaged<AppDelegate>.fromOpaque(context).takeUnretainedValue()
            if !delegate.launcher.isRecordingShortcut { delegate.launcher.toggle() }
            return noErr
        }, 1, &type, context, &handler)
        let configured = LauncherConfiguration.shared.hotKey
        let status = registerHotKey(configured)
        launcher.onHotKeyChange = { [weak self] value in
            guard let self = self else { return "Launcher is unavailable." }
            if value == LauncherConfiguration.shared.hotKey { return nil }
            let status = self.registerHotKey(value)
            if status == noErr { LauncherConfiguration.shared.setHotKey(value); return nil }
            return "That shortcut is unavailable. Your previous shortcut is still active."
        }
        NSLog("Quick Launch: event handler=%d; shortcut registration=%d", installStatus, status)
        let backgroundLaunch = CommandLine.arguments.contains("--background")
        if status != noErr || installStatus != noErr {
            launcher.reportShortcutError("\(configured.title) could not be activated. Choose another shortcut or use the menu bar icon.")
            if backgroundLaunch { return }
            DispatchQueue.main.async {
                let alert = NSAlert()
                alert.messageText = "The launcher shortcut is unavailable"
                alert.informativeText = "Choose another shortcut in Quick Launch settings, or release the conflicting shortcut in System Settings. You can open the launcher from its menu bar icon. (Registration: \(status), handler: \(installStatus))"
                alert.addButton(withTitle: "OK")
                NSApp.activate(ignoringOtherApps: true)
                alert.runModal()
            }
        } else if !backgroundLaunch {
            launcher.toggle()
        }
    }

    private func registerHotKey(_ value: LauncherHotKey) -> OSStatus {
        guard value.isValid else { return OSStatus(paramErr) }
        var modifiers: UInt32 = 0
        for (bit, carbon): (UInt32, Int) in [(1, cmdKey), (2, optionKey), (4, controlKey), (8, shiftKey)] {
            if value.modifiers & bit != 0 { modifiers |= UInt32(carbon) }
        }
        var replacement: EventHotKeyRef?
        let id = EventHotKeyID(signature: 0x514C4348, id: 1)
        let status = RegisterEventHotKey(value.keyCode, modifiers, id, GetApplicationEventTarget(), 0, &replacement)
        if status == noErr {
            if let previous = hotKey {
                let removed = UnregisterEventHotKey(previous)
                if removed != noErr {
                    if let replacement = replacement { UnregisterEventHotKey(replacement) }
                    return removed
                }
            }
            hotKey = replacement
        }
        return status
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !launcher.panel.isVisible { launcher.toggle() }
        return true
    }
    func applicationWillTerminate(_ notification: Notification) {
        launcher?.dismiss()
        if let hotKey = hotKey { UnregisterEventHotKey(hotKey) }
        if let handler = handler { RemoveEventHandler(handler) }
    }
    @objc private func showLauncher() { if !launcher.panel.isVisible { launcher.toggle() } }
    @objc private func enableAnimations() { launcher.requestWindowAnimationPermission() }
    @objc private func refresh() { launcher.refreshIndex(force: true) }
    @objc private func quit() { NSApp.terminate(nil) }
}

let application = NSApplication.shared
let delegate = AppDelegate()
application.setActivationPolicy(.accessory)
application.delegate = delegate
application.run()
