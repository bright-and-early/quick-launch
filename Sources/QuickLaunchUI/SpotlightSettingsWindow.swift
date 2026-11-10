import AppKit
import QuickLaunchCore

private final class ServiceCheckbox: NSButton {
    override var allowsVibrancy: Bool { false }
}

final class SpotlightSettingsWindow: NSObject, NSTableViewDataSource, NSTableViewDelegate {
    private let parent: NSWindow
    private let sheet = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 740, height: 500), styleMask: [.titled], backing: .buffered, defer: false)
    private let table = NSTableView()
    private let message = NSTextField(wrappingLabelWithString: "")
    private var services: [SpotlightService] = []
    private var selected = Set<String>()
    private var outcomes: [String: String] = [:]
    private var controls: [NSButton] = []
    private var busy = false
    var onClose: (() -> Void)?

    init(parent: NSWindow) {
        self.parent = parent
        super.init()
        sheet.title = "Spotlight services"
        let content = NSVisualEffectView(frame: sheet.contentView!.bounds)
        content.material = .hudWindow; content.blendingMode = .withinWindow; content.state = .active; content.wantsLayer = true
        sheet.contentView = content
        let impact = NSTextField(wrappingLabelWithString: "Disabling these services affects Spotlight indexing, Finder and app searches, and search suggestions. Quick Launch uses its own index. macOS may refuse changes to protected services. Enabling allows services to load again; it does not start them immediately.")
        impact.font = .systemFont(ofSize: 12)
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        table.headerView = nil; table.rowHeight = 51
        table.frame = NSRect(x: 0, y: 0, width: 700, height: 280)
        table.autoresizingMask = [.width]
        table.addTableColumn(NSTableColumn(identifier: .init("service")))
        table.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        table.dataSource = self; table.delegate = self
        scroll.documentView = table
        let buttons = NSStackView()
        buttons.orientation = .horizontal; buttons.spacing = 10
        for (title, selector) in [("Select all", #selector(selectAll(_:))), ("Disable selected…", #selector(disable(_:))), ("Enable selected…", #selector(enable(_:))), ("Refresh", #selector(refresh(_:))), ("Close", #selector(close(_:)))] {
            let button = NSButton(title: title, target: self, action: selector)
            if title == "Close" { button.keyEquivalent = "\u{1b}" }
            buttons.addArrangedSubview(button); controls.append(button)
        }
        message.font = .systemFont(ofSize: 12)
        for view in [impact, scroll, message, buttons] { view.translatesAutoresizingMaskIntoConstraints = false; content.addSubview(view) }
        NSLayoutConstraint.activate([
            impact.topAnchor.constraint(equalTo: content.topAnchor, constant: 18), impact.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20), impact.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            scroll.topAnchor.constraint(equalTo: impact.bottomAnchor, constant: 14), scroll.leadingAnchor.constraint(equalTo: impact.leadingAnchor), scroll.trailingAnchor.constraint(equalTo: impact.trailingAnchor),
            message.topAnchor.constraint(equalTo: scroll.bottomAnchor, constant: 10), message.leadingAnchor.constraint(equalTo: impact.leadingAnchor), message.trailingAnchor.constraint(equalTo: impact.trailingAnchor), message.heightAnchor.constraint(equalToConstant: 46),
            buttons.topAnchor.constraint(equalTo: message.bottomAnchor, constant: 10), buttons.trailingAnchor.constraint(equalTo: impact.trailingAnchor), buttons.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -16)
        ])
    }

    func present() { parent.beginSheet(sheet); refresh(nil) }
    static func evidence(services: [SpotlightService]) -> (AnyObject, NSView) {
        let controller = SpotlightSettingsWindow(parent: NSPanel())
        controller.services = services
        controller.selected = Set(services.map(\.target))
        controller.message.stringValue = "Review the selected services before applying changes."
        controller.table.reloadData()
        controller.sheet.contentView!.layoutSubtreeIfNeeded()
        return (controller, controller.sheet.contentView!)
    }
    func numberOfRows(in tableView: NSTableView) -> Int { services.count }
    func tableView(_ tableView: NSTableView, viewFor column: NSTableColumn?, row: Int) -> NSView? {
        let service = services[row]
        let view = NSView()
        view.wantsLayer = true
        let checkbox = ServiceCheckbox(checkboxWithTitle: service.label + " · " + service.domain, target: self, action: #selector(toggleService(_:)))
        checkbox.wantsLayer = true
        checkbox.tag = row; checkbox.state = selected.contains(service.target) ? .on : .off
        checkbox.isEnabled = !busy; checkbox.toolTip = service.target
        let detail = NSTextField(labelWithString: outcomes[service.target] ?? service.state)
        detail.font = .systemFont(ofSize: 11); detail.textColor = .secondaryLabelColor; detail.lineBreakMode = .byTruncatingTail
        for child in [checkbox, detail] { child.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(child) }
        NSLayoutConstraint.activate([
            checkbox.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 8), checkbox.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -8), checkbox.topAnchor.constraint(equalTo: view.topAnchor, constant: 5),
            detail.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 28), detail.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -8), detail.topAnchor.constraint(equalTo: checkbox.bottomAnchor, constant: 3)
        ])
        detail.toolTip = detail.stringValue
        return view
    }
    @objc private func toggleService(_ sender: NSButton) {
        guard services.indices.contains(sender.tag), !busy else { return }
        let target = services[sender.tag].target
        if sender.state == .on { selected.insert(target) } else { selected.remove(target) }
    }
    @objc private func selectAll(_ sender: Any?) { selected = Set(services.map(\.target)); table.reloadData() }
    private func setBusy(_ value: Bool) { busy = value; controls.forEach { $0.isEnabled = !value }; table.reloadData() }
    @objc private func close(_ sender: Any?) { guard !busy else { return }; parent.endSheet(sheet); sheet.orderOut(nil); onClose?() }
    @objc private func refresh(_ sender: Any?) {
        guard !busy else { return }
        setBusy(true); message.stringValue = "Reading Spotlight services…"
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let inventory = SpotlightServices.discover(uid: getuid(), run: SystemCommand.launchctl)
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.services = inventory.services
                self.selected = Set(inventory.services.filter { $0.loaded || $0.disabled != true }.map(\.target))
                self.outcomes = [:]; self.setBusy(false)
                self.message.stringValue = inventory.errors.isEmpty ? (inventory.services.isEmpty ? "No matching services were discovered." : "Review the selected services before applying changes.") : inventory.errors.joined(separator: "\n")
            }
        }
    }
    @objc private func disable(_ sender: Any?) { confirm(disabled: true) }
    @objc private func enable(_ sender: Any?) { confirm(disabled: false) }
    private func confirm(disabled: Bool) {
        let jobs = services.filter { selected.contains($0.target) }
        guard !busy, !jobs.isEmpty else { message.stringValue = "Select at least one service."; return }
        let alert = NSAlert()
        alert.messageText = "\(disabled ? "Disable" : "Enable") \(jobs.count) selected services?"
        alert.informativeText = disabled ? "This saves a disabled launch policy and stops each selected job. A before/after report is saved. macOS will ask for administrator authorization." : "This removes the disabled policy. Services can load again at login or reboot; no job is started by this action."
        alert.addButton(withTitle: disabled ? "Disable selected" : "Enable selected")
        alert.addButton(withTitle: "Cancel")
        alert.beginSheetModal(for: sheet) { [weak self] response in
            if response == .alertFirstButtonReturn { self?.apply(SpotlightRequest(services: jobs, disabled: disabled)) }
        }
    }
    private func apply(_ request: SpotlightRequest) {
        guard request.isValid, let executable = Bundle.main.executableURL else { return }
        let directory = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/QuickLaunch/SpotlightReports")
        let receipt = directory.appendingPathComponent(request.id.uuidString + ".json")
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            try JSONEncoder().encode(request).write(to: receipt, options: .atomic)
        } catch { message.stringValue = "No services changed: could not save the original state. " + error.localizedDescription; return }
        setBusy(true); message.stringValue = "Waiting for authorization and verifying each selected service…"
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            func shellQuote(_ value: String) -> String { "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'" }
            let encoded = (try! JSONEncoder().encode(request)).base64EncodedString()
            let command = [executable.path, "--spotlight-apply", encoded].map(shellQuote).joined(separator: " ")
            let script = "do shell script \"" + command.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\" with administrator privileges"
            let result = SystemCommand.run("/usr/bin/osascript", ["-e", script], timeout: nil)
            var journal = SpotlightJournal.read(request.id)
            let decoded = try? JSONDecoder().decode([SpotlightChange].self, from: Data(result.output.utf8))
            let knownNotStarted = journal.isEmpty && (result.error.contains("(-128)") || result.error.contains("NO_CHANGES:"))
            // If the authorization wrapper exits unexpectedly, keep the workflow
            // busy until the helper completes or its process is known to have exited.
            while SpotlightOperationRecovery.shouldWait(wrapperFailed: !knownNotStarted && (result.status != 0 || decoded == nil), deadline: request.deadline, records: journal, helperRunning: { kill($0, 0) == 0 || errno != ESRCH }) {
                DispatchQueue.main.async { [weak self] in self?.message.stringValue = "Verifying whether the authorized operation is still running…" }
                Thread.sleep(forTimeInterval: 0.5)
                journal = SpotlightJournal.read(request.id)
            }
            let changes = decoded ?? (journal.isEmpty ? nil : journal.compactMap(\.change))
            var saveError = ""
            if let changes = changes {
                do { try JSONEncoder().encode(changes).write(to: receipt, options: .atomic) } catch { saveError = " Could not save final results: " + error.localizedDescription }
            }
            let inventory = SpotlightServices.discover(uid: getuid(), run: SystemCommand.launchctl)
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.services = inventory.services
                self.outcomes = Dictionary((changes ?? []).map { ($0.service.target, ($0.succeeded ? "✓ " : "Not completed: ") + $0.detail) }, uniquingKeysWith: { _, last in last })
                self.setBusy(false)
                if let changes = changes {
                    let interrupted = journal.last?.phase == "complete" ? "" : "Operation interrupted; inspect the journal before retrying. "
                    self.message.stringValue = interrupted + "\(changes.filter(\.succeeded).count) of \(request.services.count) verified. Journals: /Library/Application Support/QuickLaunch/SpotlightReports." + saveError + inventory.errors.joined(separator: "\n")
                } else { self.message.stringValue = "Change was cancelled or could not be verified. " + result.error + saveError }
            }
        }
    }
}

@_spi(Testing) public func spotlightServiceEvidence(_ services: [SpotlightService]) -> (AnyObject, NSView) {
    SpotlightSettingsWindow.evidence(services: services)
}
