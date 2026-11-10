import AppKit
import QuickLaunchCore

public final class SearchPanel: NSPanel {
    public override var canBecomeKey: Bool { true }
    public override var canBecomeMain: Bool { false }
    public var onDismiss: (() -> Void)?
    public override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown && event.keyCode == 53 { cancelOperation(nil); return }
        super.sendEvent(event)
    }
    public override func cancelOperation(_ sender: Any?) {
        if let onDismiss = onDismiss { onDismiss() } else { orderOut(nil) }
    }
}

public final class LauncherController: NSObject, NSTextFieldDelegate, NSWindowDelegate, NSTableViewDataSource, NSTableViewDelegate {
    public let panel: SearchPanel
    private let field = NSTextField()
    private let resultsScroll = NSScrollView()
    private let resultsTable = NSTableView()
    private let emptySearchDrag = DragSurface()
    private let iconDrag = DragSurface()
    private let projectButtons = NSStackView()
    private let settingsButton = ProjectShortcutButton()
    private let settingsDivider = NSBox()
    private let reverse = NSVisualEffectView()
    private let backButton = ProjectShortcutButton()
    private var colorButtons: [ProjectShortcutButton] = []
    private var faces: LauncherFaces!
    private var projectApplications: [Application] = []
    private var fieldTrailingToProjects: NSLayoutConstraint!
    private var fieldTrailingToEdge: NSLayoutConstraint!
    private let content = NSVisualEffectView()
    private let emptyLabel = NSTextField(labelWithString: "")
    private var applications: [Application] = []
    private var matches: [Application] = []
    private var selected = 0
    private var icons: [URL: NSImage] = [:]
    private var scanning = false
    private var lastScan = Date.distantPast
    private var outsideClickMonitor: Any?
    private var localClickMonitor: Any?
    private var previousFrontmost: NSRunningApplication?
    private var presentationID = UUID()
    private let projectTransitions = ProjectAppTransitions()
    private let openHistory = ApplicationOpenHistory()
    var onLaunch: ((Application) -> Void)?

    public override init() {
        panel = SearchPanel(contentRect: NSRect(x: 0, y: 0, width: 640, height: 78),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        super.init()
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.delegate = self
        panel.onDismiss = { [weak self] in self?.dismiss() }
        panel.title = "Quick Launch"
        content.material = .hudWindow
        content.blendingMode = .behindWindow
        content.state = .active
        content.wantsLayer = true
        content.layer?.cornerRadius = 16
        faces = LauncherFaces(front: content, reverse: reverse)
        panel.contentView = faces
        faces.onSettled = { [weak self] back in
            guard let self = self else { return }
            if back { self.panel.makeFirstResponder(self.backButton) }
            else { self.focusSearch() }
        }
        configureSettings()

        let symbol = NSImageView(image: NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: nil)!)
        symbol.contentTintColor = .secondaryLabelColor
        symbol.imageScaling = .scaleProportionallyUpOrDown
        symbol.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(symbol)
        field.translatesAutoresizingMaskIntoConstraints = false
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: 23, weight: .regular)
        field.placeholderString = "Search applications"
        field.setAccessibilityLabel("Search applications")
        field.delegate = self
        content.addSubview(field)
        emptySearchDrag.wantsLayer = true
        emptySearchDrag.focusField = field
        emptySearchDrag.translatesAutoresizingMaskIntoConstraints = false
        emptySearchDrag.setAccessibilityElement(false)
        content.addSubview(emptySearchDrag)
        iconDrag.wantsLayer = true
        iconDrag.focusField = field
        iconDrag.translatesAutoresizingMaskIntoConstraints = false
        iconDrag.setAccessibilityElement(false)
        content.addSubview(iconDrag)
        projectButtons.orientation = .horizontal
        projectButtons.spacing = 8
        projectButtons.alignment = .centerY
        projectButtons.translatesAutoresizingMaskIntoConstraints = false
        projectButtons.setContentHuggingPriority(.required, for: .horizontal)
        projectButtons.setContentCompressionResistancePriority(.required, for: .horizontal)
        projectButtons.isHidden = true
        content.addSubview(projectButtons)
        fieldTrailingToProjects = field.trailingAnchor.constraint(equalTo: projectButtons.leadingAnchor, constant: -16)
        fieldTrailingToEdge = field.trailingAnchor.constraint(equalTo: settingsButton.leadingAnchor, constant: -16)
        resultsScroll.translatesAutoresizingMaskIntoConstraints = false
        resultsScroll.drawsBackground = false
        resultsScroll.borderType = .noBorder
        resultsScroll.hasVerticalScroller = true
        resultsScroll.autohidesScrollers = true
        resultsScroll.hasHorizontalScroller = false
        resultsScroll.horizontalScrollElasticity = .none
        resultsScroll.automaticallyAdjustsContentInsets = false
        resultsTable.headerView = nil
        resultsTable.backgroundColor = .clear
        resultsTable.style = .plain
        resultsTable.rowHeight = 54
        resultsTable.intercellSpacing = NSSize(width: 0, height: 4)
        resultsTable.usesAutomaticRowHeights = false
        resultsTable.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        resultsTable.autoresizingMask = [.width]
        resultsTable.focusRingType = .none
        resultsTable.allowsMultipleSelection = false
        resultsTable.allowsColumnResizing = false
        resultsTable.allowsColumnReordering = false
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("applications"))
        column.width = 620
        column.minWidth = 1
        resultsTable.addTableColumn(column)
        resultsTable.dataSource = self
        resultsTable.delegate = self
        resultsTable.target = self
        resultsTable.action = #selector(clickResult(_:))
        resultsScroll.documentView = resultsTable
        content.addSubview(resultsScroll)
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        emptyLabel.textColor = .secondaryLabelColor
        emptyLabel.font = .systemFont(ofSize: 14)
        content.addSubview(emptyLabel)
        NSLayoutConstraint.activate([
            symbol.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 22),
            symbol.topAnchor.constraint(equalTo: content.topAnchor, constant: 26),
            symbol.widthAnchor.constraint(equalToConstant: 26), symbol.heightAnchor.constraint(equalToConstant: 26),
            field.leadingAnchor.constraint(equalTo: symbol.trailingAnchor, constant: 16),
            fieldTrailingToEdge,
            projectButtons.trailingAnchor.constraint(equalTo: settingsDivider.leadingAnchor, constant: -12),
            projectButtons.centerYAnchor.constraint(equalTo: field.centerYAnchor),
            field.topAnchor.constraint(equalTo: content.topAnchor, constant: 20),
            field.heightAnchor.constraint(equalToConstant: 38),
            emptySearchDrag.leadingAnchor.constraint(equalTo: field.leadingAnchor),
            emptySearchDrag.trailingAnchor.constraint(equalTo: field.trailingAnchor),
            emptySearchDrag.topAnchor.constraint(equalTo: field.topAnchor),
            emptySearchDrag.bottomAnchor.constraint(equalTo: field.bottomAnchor),
            iconDrag.leadingAnchor.constraint(equalTo: symbol.leadingAnchor),
            iconDrag.trailingAnchor.constraint(equalTo: symbol.trailingAnchor),
            iconDrag.topAnchor.constraint(equalTo: symbol.topAnchor),
            iconDrag.bottomAnchor.constraint(equalTo: symbol.bottomAnchor),
            resultsScroll.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 10),
            resultsScroll.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -10),
            resultsScroll.topAnchor.constraint(equalTo: content.topAnchor, constant: 76),
            resultsScroll.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -10),
            emptyLabel.leadingAnchor.constraint(equalTo: resultsScroll.leadingAnchor, constant: 12),
            emptyLabel.trailingAnchor.constraint(equalTo: resultsScroll.trailingAnchor, constant: -12),
            emptyLabel.topAnchor.constraint(equalTo: resultsScroll.topAnchor),
            emptyLabel.heightAnchor.constraint(equalToConstant: 44)
        ])
        installDismissalMonitors()
        refreshIndex(force: true)
    }

    private func configureSettings() {
        settingsButton.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: nil)?.withSymbolConfiguration(.init(pointSize: 20, weight: .regular))
        settingsButton.target = self
        settingsButton.action = #selector(showSettings(_:))
        settingsButton.tag = -1
        settingsButton.toolTip = "Settings"
        settingsButton.setAccessibilityLabel("Settings")
        settingsButton.isBordered = false
        settingsButton.focusRingType = .none
        settingsButton.translatesAutoresizingMaskIntoConstraints = false
        settingsButton.navigate = { [weak self] offset, _ in
            guard let self = self else { return }
            if offset < 0, let last = self.projectButtons.arrangedSubviews.last { self.panel.makeFirstResponder(last) }
            else { self.focusSearch() }
        }
        content.addSubview(settingsButton)
        settingsDivider.boxType = .separator
        settingsDivider.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(settingsDivider)
        reverse.material = .hudWindow
        reverse.blendingMode = .behindWindow
        reverse.state = .active
        reverse.layer?.cornerRadius = 16
        backButton.image = NSImage(systemSymbolName: "arrow.left", accessibilityDescription: nil)
        backButton.target = self
        backButton.action = #selector(showSearch(_:))
        backButton.tag = -2
        backButton.toolTip = "Back to search"
        backButton.setAccessibilityLabel("Back to search")
        backButton.isBordered = false
        backButton.focusRingType = .none
        backButton.translatesAutoresizingMaskIntoConstraints = false
        backButton.navigate = { [weak self] offset, _ in
            guard let self = self else { return }
            self.panel.makeFirstResponder(offset > 0 ? self.colorButtons.first : self.colorButtons.last)
        }
        reverse.addSubview(backButton)
        let title = NSTextField(labelWithString: "Settings")
        title.font = .systemFont(ofSize: 23)
        title.translatesAutoresizingMaskIntoConstraints = false
        reverse.addSubview(title)
        let colorLabel = NSTextField(labelWithString: "Highlight color")
        colorLabel.font = .systemFont(ofSize: 14, weight: .medium)
        colorLabel.translatesAutoresizingMaskIntoConstraints = false
        reverse.addSubview(colorLabel)
        let swatches = NSStackView()
        swatches.orientation = .horizontal
        swatches.spacing = 10
        swatches.translatesAutoresizingMaskIntoConstraints = false
        reverse.addSubview(swatches)
        for (index, color) in HighlightColor.allCases.enumerated() {
            let button = ProjectShortcutButton()
            button.tag = -10 - index
            button.target = self
            button.action = #selector(changeHighlight(_:))
            button.toolTip = color.title
            button.setAccessibilityLabel(color.title)
            button.isBordered = false
            button.focusRingType = .none
            button.contentTintColor = color.color
            button.navigate = { [weak self] offset, _ in
                guard let self = self else { return }
                let next = index + offset
                self.panel.makeFirstResponder(self.colorButtons.indices.contains(next) ? self.colorButtons[next] : self.backButton)
            }
            colorButtons.append(button)
            swatches.addArrangedSubview(button)
            button.widthAnchor.constraint(equalToConstant: 32).isActive = true
            button.heightAnchor.constraint(equalToConstant: 32).isActive = true
        }
        updateColorButtons()
        NSLayoutConstraint.activate([
            settingsButton.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -22),
            settingsButton.topAnchor.constraint(equalTo: content.topAnchor, constant: 23),
            settingsButton.widthAnchor.constraint(equalToConstant: 32), settingsButton.heightAnchor.constraint(equalToConstant: 32),
            settingsDivider.trailingAnchor.constraint(equalTo: settingsButton.leadingAnchor, constant: -10),
            settingsDivider.centerYAnchor.constraint(equalTo: settingsButton.centerYAnchor),
            settingsDivider.widthAnchor.constraint(equalToConstant: 1), settingsDivider.heightAnchor.constraint(equalToConstant: 22),
            backButton.leadingAnchor.constraint(equalTo: reverse.leadingAnchor, constant: 22),
            backButton.topAnchor.constraint(equalTo: reverse.topAnchor, constant: 23),
            backButton.widthAnchor.constraint(equalToConstant: 32), backButton.heightAnchor.constraint(equalToConstant: 32),
            title.leadingAnchor.constraint(equalTo: backButton.trailingAnchor, constant: 14),
            title.centerYAnchor.constraint(equalTo: backButton.centerYAnchor),
            colorLabel.leadingAnchor.constraint(equalTo: reverse.leadingAnchor, constant: 26),
            colorLabel.topAnchor.constraint(equalTo: reverse.topAnchor, constant: 84),
            swatches.leadingAnchor.constraint(equalTo: colorLabel.trailingAnchor, constant: 18),
            swatches.centerYAnchor.constraint(equalTo: colorLabel.centerYAnchor)
        ])
    }

    @objc private func showSettings(_ sender: Any?) {
        guard !faces.isFlipping && !projectTransitions.isBusy else { return }
        faces.setShowingBack(true, animated: panel.isVisible)
    }

    @objc private func showSearch(_ sender: Any?) {
        guard !faces.isFlipping else { return }
        faces.setShowingBack(false, animated: panel.isVisible)
    }

    @objc private func changeHighlight(_ sender: NSButton) {
        let index = -sender.tag - 10
        guard HighlightColor.allCases.indices.contains(index) else { return }
        LauncherAppearance.shared.choose(HighlightColor.allCases[index])
        updateColorButtons()
        func redraw(_ view: NSView) { view.needsDisplay = true; view.subviews.forEach(redraw) }
        redraw(faces)
    }

    private func updateColorButtons() {
        for (index, button) in colorButtons.enumerated() {
            let selected = HighlightColor.allCases[index] == LauncherAppearance.shared.highlight
            button.image = NSImage(systemSymbolName: selected ? "checkmark.circle.fill" : "circle.fill", accessibilityDescription: nil)?.withSymbolConfiguration(.init(pointSize: 24, weight: .regular))
            button.setAccessibilityValue(selected ? "Selected" : "")
        }
    }

    deinit {
        if let monitor = outsideClickMonitor { NSEvent.removeMonitor(monitor) }
        if let monitor = localClickMonitor { NSEvent.removeMonitor(monitor) }
    }

    private func installDismissalMonitors() {
        let mouseEvents: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: mouseEvents) { [weak self] _ in
            self?.dismissIfOutside(NSEvent.mouseLocation)
        }
        localClickMonitor = NSEvent.addLocalMonitorForEvents(matching: mouseEvents) { [weak self] event in
            let point = event.window?.convertPoint(toScreen: event.locationInWindow) ?? NSEvent.mouseLocation
            self?.dismissIfOutside(point)
            return event
        }
    }

    private func dismissIfOutside(_ point: NSPoint) {
        if LauncherDismissal.shouldDismiss(click: point, panel: panel.frame, isVisible: panel.isVisible) { dismiss() }
    }

    public func refreshIndex(force: Bool = false) {
        guard !scanning, force || Date().timeIntervalSince(lastScan) > 30 else { return }
        scanning = true
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let inventory = ApplicationIndex.scan()
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.applications = inventory
                self.updateProjectShortcuts()
                self.scanning = false
                self.lastScan = Date()
                self.updateResults()
            }
        }
    }

    public func toggle() {
        if panel.isVisible { dismiss(); return }
        presentationID = UUID()
        faces.setShowingBack(false, animated: false)
        if let front = NSWorkspace.shared.frontmostApplication, front.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            previousFrontmost = front
        }
        refreshIndex()
        field.stringValue = ""
        selected = 0
        updateResults()
        let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.main!
        let area = screen.visibleFrame
        let width = min(640, area.width - 40)
        let proposed = NSRect(x: area.midX - width / 2, y: area.minY + area.height * 0.68 - panel.frame.height, width: width, height: panel.frame.height)
        panel.setFrame(PanelPlacement.fitted(proposed, in: area), display: true)
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(field)
    }

    private var targetScreen: NSScreen {
        if panel.isVisible, let screen = panel.screen { return screen }
        return NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.main!
    }

    public func dismiss() {
        presentationID = UUID()
        projectTransitions.cancel()
        panel.orderOut(nil)
        faces.setShowingBack(false, animated: false)
    }
    public func requestWindowAnimationPermission() { projectTransitions.requestPermission() }
    public func windowDidResignKey(_ notification: Notification) {
        if !projectTransitions.isBusy { dismiss() }
    }
    public func controlTextDidChange(_ obj: Notification) {
        selected = 0
        updateResults()
    }

    public func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        switch commandSelector {
        case #selector(NSResponder.moveRight(_:)), #selector(NSResponder.moveForward(_:)):
            let range = textView.selectedRange()
            guard range.length == 0, range.location == (textView.string as NSString).length,
                  !faces.showingBack else { return false }
            return panel.makeFirstResponder(projectButtons.arrangedSubviews.first ?? settingsButton)
        case #selector(NSResponder.moveDown(_:)):
            moveSelection(by: 1); return true
        case #selector(NSResponder.moveUp(_:)):
            moveSelection(by: -1); return true
        case #selector(NSResponder.insertNewline(_:)):
            launchSelection(); return true
        case #selector(NSResponder.cancelOperation(_:)):
            dismiss(); return true
        case #selector(NSResponder.insertTab(_:)):
            guard matches.indices.contains(selected) else { return true }
            field.stringValue = matches[selected].name
            selected = 0
            updateResults()
            textView.setSelectedRange(NSRange(location: (field.stringValue as NSString).length, length: 0))
            return true
        default: return false
        }
    }

    private func updateResults() {
        matches = AppSearch.results(for: field.stringValue, in: applications, limit: applications.count, openCounts: openHistory.counts)
        emptySearchDrag.isHidden = !field.stringValue.isEmpty
        selected = max(0, min(selected, matches.count - 1))
        drawRows()
    }

    private func drawRows() {
        let visibleCount = min(matches.count, PanelPlacement.resultLimit(in: targetScreen.visibleFrame))
        let height = CGFloat(76 + (matches.isEmpty ? 44 : visibleCount * 58) + 10)
        let top = panel.frame.maxY
        let proposed = NSRect(x: panel.frame.minX, y: top - height, width: panel.frame.width, height: height)
        if !faces.showingBack && !faces.isFlipping {
            panel.setFrame(PanelPlacement.fitted(proposed, in: targetScreen.visibleFrame), display: true)
        }
        emptyLabel.stringValue = scanning ? "Loading applications…" : "No applications found"
        emptyLabel.isHidden = !matches.isEmpty
        resultsScroll.isHidden = matches.isEmpty
        resultsTable.reloadData()
        if !matches.isEmpty {
            resultsTable.selectRowIndexes(IndexSet(integer: selected), byExtendingSelection: false)
            resultsTable.scrollRowToVisible(selected)
        }
    }

    private func moveSelection(by offset: Int) {
        guard !matches.isEmpty else { return }
        selected = max(0, min(matches.count - 1, selected + offset))
        resultsTable.selectRowIndexes(IndexSet(integer: selected), byExtendingSelection: false)
        resultsTable.scrollRowToVisible(selected)
    }

    public func numberOfRows(in tableView: NSTableView) -> Int { matches.count }

    public func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard matches.indices.contains(row) else { return nil }
        let identifier = NSUserInterfaceItemIdentifier("application-result")
        let cell = tableView.makeView(withIdentifier: identifier, owner: self) as? ApplicationResultCell
            ?? ApplicationResultCell(frame: .zero)
        cell.identifier = identifier
        cell.configure(matches[row], icon: appIcon(for: matches[row]))
        return cell
    }

    public func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        ResultRowView()
    }

    public func tableViewSelectionDidChange(_ notification: Notification) {
        if resultsTable.selectedRow >= 0 { selected = resultsTable.selectedRow }
    }

    @objc private func clickResult(_ tableView: NSTableView) {
        let row = tableView.clickedRow
        guard matches.indices.contains(row) else { return }
        openApplication(matches[row])
    }

    private func appIcon(for application: Application) -> NSImage {
        if let cached = icons[application.url] { return cached }
        let image = NSWorkspace.shared.icon(forFile: application.url.path)
        icons[application.url] = image
        return image
    }

    private func updateProjectShortcuts() {
        let focusedURL = (panel.firstResponder as? ProjectShortcutButton).flatMap { button in
            projectApplications.indices.contains(button.tag) ? projectApplications[button.tag].url : nil
        }
        for button in projectButtons.arrangedSubviews {
            projectButtons.removeArrangedSubview(button)
            button.removeFromSuperview()
        }
        projectApplications = ProjectShortcuts.applications(in: applications)
        for (index, application) in projectApplications.enumerated() {
            let button = ProjectShortcutButton(image: appIcon(for: application), target: self, action: #selector(clickProject(_:)))
            button.isBordered = false
            button.imagePosition = .imageOnly
            button.imageScaling = .scaleProportionallyUpOrDown
            button.refusesFirstResponder = false
            button.focusRingType = .none
            button.navigate = { [weak self] offset, tab in self?.moveProjectFocus(from: index, by: offset, tab: tab) }
            button.toolTip = application.name
            button.setAccessibilityLabel("Toggle \(application.name)")
            button.tag = index
            projectButtons.addArrangedSubview(button)
            button.widthAnchor.constraint(equalToConstant: 32).isActive = true
            button.heightAnchor.constraint(equalToConstant: 32).isActive = true
        }
        let hasProjects = !projectApplications.isEmpty
        fieldTrailingToEdge.isActive = !hasProjects
        fieldTrailingToProjects.isActive = hasProjects
        projectButtons.isHidden = !hasProjects
        settingsDivider.isHidden = !hasProjects
        if let focusedURL = focusedURL {
            if let index = projectApplications.firstIndex(where: { $0.url == focusedURL }) {
                panel.makeFirstResponder(projectButtons.arrangedSubviews[index])
            } else { focusSearch() }
        }
    }

    private func focusSearch() {
        panel.makeFirstResponder(field)
        field.currentEditor()?.selectedRange = NSRange(location: (field.stringValue as NSString).length, length: 0)
    }

    private func moveProjectFocus(from index: Int, by offset: Int, tab: Bool) {
        let next = index + offset
        if next < 0 {
            focusSearch()
        } else if next >= projectButtons.arrangedSubviews.count {
            panel.makeFirstResponder(settingsButton)
        } else if projectButtons.arrangedSubviews.indices.contains(next) {
            panel.makeFirstResponder(projectButtons.arrangedSubviews[next])
        }
    }

    @objc private func clickProject(_ sender: NSButton) {
        guard projectApplications.indices.contains(sender.tag) else { return }
        let application = projectApplications[sender.tag]
        let anchor = panel.convertToScreen(sender.convert(sender.bounds, to: nil))
        let opening = presentationID
        projectTransitions.toggle(application, anchor: anchor, previousFrontmost: previousFrontmost, opened: { [weak self] in
            self?.openHistory.recordOpen(application)
        }) { [weak self] in
            guard let self = self, self.presentationID == opening else { return }
            self.panel.orderOut(nil)
        }
    }

    private func launchSelection() {
        guard matches.indices.contains(selected) else { return }
        openApplication(matches[selected])
    }

    private func openApplication(_ app: Application) {
        dismiss()
        onLaunch?(app)
        NSWorkspace.shared.openApplication(at: app.url, configuration: .init()) { [weak self] running, error in
            if error == nil, running != nil {
                DispatchQueue.main.async { self?.openHistory.recordOpen(app) }
            }
            if let error = error {
                DispatchQueue.main.async {
                    let alert = NSAlert()
                    alert.messageText = "Could not open \(app.name)"
                    alert.informativeText = error.localizedDescription
                    alert.runModal()
                }
            }
        }
    }
}
