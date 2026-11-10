import AppKit
import QuickLaunchCore

final class SearchPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

final class LauncherController: NSObject, NSTextFieldDelegate, NSWindowDelegate {
    let panel: SearchPanel
    private let field = NSTextField()
    private let rows = NSStackView()
    private let content = NSVisualEffectView()
    private let emptyLabel = NSTextField(labelWithString: "")
    private var applications: [Application] = []
    private var matches: [Application] = []
    private var selected = 0
    private var icons: [URL: NSImage] = [:]
    private var scanning = false
    private var lastScan = Date.distantPast
    var onLaunch: ((Application) -> Void)?

    override init() {
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
        panel.title = "Quick Launch"
        content.material = .hudWindow
        content.blendingMode = .behindWindow
        content.state = .active
        content.wantsLayer = true
        content.layer?.cornerRadius = 16
        panel.contentView = content

        let symbol = NSImageView(image: NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: nil)!)
        symbol.contentTintColor = .secondaryLabelColor
        symbol.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(symbol)
        field.translatesAutoresizingMaskIntoConstraints = false
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: 26, weight: .regular)
        field.placeholderString = "Search applications"
        field.setAccessibilityLabel("Search applications")
        field.delegate = self
        content.addSubview(field)
        rows.orientation = .vertical
        rows.spacing = 4
        rows.alignment = .leading
        rows.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(rows)
        emptyLabel.heightAnchor.constraint(equalToConstant: 44).isActive = true
        NSLayoutConstraint.activate([
            symbol.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 22),
            symbol.topAnchor.constraint(equalTo: content.topAnchor, constant: 25),
            symbol.widthAnchor.constraint(equalToConstant: 25), symbol.heightAnchor.constraint(equalToConstant: 25),
            field.leadingAnchor.constraint(equalTo: symbol.trailingAnchor, constant: 16),
            field.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -22),
            field.topAnchor.constraint(equalTo: content.topAnchor, constant: 20),
            field.heightAnchor.constraint(equalToConstant: 38),
            rows.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 10),
            rows.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -10),
            rows.topAnchor.constraint(equalTo: content.topAnchor, constant: 76)
        ])
        refreshIndex(force: true)
    }

    func refreshIndex(force: Bool = false) {
        guard !scanning, force || Date().timeIntervalSince(lastScan) > 30 else { return }
        scanning = true
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let inventory = ApplicationIndex.scan()
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.applications = inventory
                self.scanning = false
                self.lastScan = Date()
                self.updateResults()
            }
        }
    }

    func toggle() {
        if panel.isVisible { dismiss(); return }
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

    func dismiss() { panel.orderOut(nil) }
    func windowDidResignKey(_ notification: Notification) { dismiss() }
    func controlTextDidChange(_ obj: Notification) {
        selected = 0
        updateResults()
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        switch commandSelector {
        case #selector(NSResponder.moveDown(_:)):
            selected = min(matches.count - 1, selected + 1); drawRows(); return true
        case #selector(NSResponder.moveUp(_:)):
            selected = max(0, selected - 1); drawRows(); return true
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
        let area = targetScreen.visibleFrame
        matches = AppSearch.results(for: field.stringValue, in: applications, limit: PanelPlacement.resultLimit(in: area))
        selected = max(0, min(selected, matches.count - 1))
        drawRows()
    }

    private func drawRows() {
        for view in rows.arrangedSubviews { rows.removeArrangedSubview(view); view.removeFromSuperview() }
        if matches.isEmpty {
            emptyLabel.stringValue = scanning ? "Loading applications…" : "No applications found"
            emptyLabel.textColor = .secondaryLabelColor
            emptyLabel.font = .systemFont(ofSize: 14)
            rows.addArrangedSubview(emptyLabel)
        } else {
            for (index, application) in matches.enumerated() {
                let row = NSButton()
                row.title = ""
                row.isBordered = false
                row.wantsLayer = true
                row.layer?.cornerRadius = 9
                row.layer?.backgroundColor = (index == selected ? NSColor.selectedContentBackgroundColor.withAlphaComponent(0.22) : .clear).cgColor
                row.tag = index
                row.target = self
                row.action = #selector(clickRow(_:))
                row.setAccessibilityLabel(application.name)
                let icon: NSImage
                if let cached = icons[application.url] { icon = cached }
                else { icon = NSWorkspace.shared.icon(forFile: application.url.path); icons[application.url] = icon }
                let image = NSImageView(image: icon)
                image.translatesAutoresizingMaskIntoConstraints = false
                let name = NSTextField(labelWithString: application.name)
                name.font = .systemFont(ofSize: 16, weight: .medium)
                name.lineBreakMode = .byTruncatingTail
                name.translatesAutoresizingMaskIntoConstraints = false
                let path = NSTextField(labelWithString: application.url.deletingLastPathComponent().path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                path.font = .systemFont(ofSize: 11)
                path.textColor = .secondaryLabelColor
                path.lineBreakMode = .byTruncatingMiddle
                path.translatesAutoresizingMaskIntoConstraints = false
                for view in [image, name, path] { row.addSubview(view) }
                rows.addArrangedSubview(row)
                NSLayoutConstraint.activate([
                    row.widthAnchor.constraint(equalTo: rows.widthAnchor), row.heightAnchor.constraint(equalToConstant: 54),
                    image.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 12), image.centerYAnchor.constraint(equalTo: row.centerYAnchor),
                    image.widthAnchor.constraint(equalToConstant: 32), image.heightAnchor.constraint(equalToConstant: 32),
                    name.leadingAnchor.constraint(equalTo: image.trailingAnchor, constant: 12), name.topAnchor.constraint(equalTo: row.topAnchor, constant: 8),
                    name.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -12),
                    path.leadingAnchor.constraint(equalTo: name.leadingAnchor), path.topAnchor.constraint(equalTo: name.bottomAnchor, constant: 3),
                    path.trailingAnchor.constraint(equalTo: name.trailingAnchor)
                ])
            }
        }
        let height = CGFloat(76 + (matches.isEmpty ? 44 : matches.count * 58) + 10)
        let top = panel.frame.maxY
        let proposed = NSRect(x: panel.frame.minX, y: top - height, width: panel.frame.width, height: height)
        panel.setFrame(PanelPlacement.fitted(proposed, in: targetScreen.visibleFrame), display: true)
    }

    @objc private func clickRow(_ sender: NSButton) { selected = sender.tag; launchSelection() }
    private func launchSelection() {
        guard matches.indices.contains(selected) else { return }
        let app = matches[selected]
        dismiss()
        onLaunch?(app)
        NSWorkspace.shared.openApplication(at: app.url, configuration: .init()) { _, error in
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
