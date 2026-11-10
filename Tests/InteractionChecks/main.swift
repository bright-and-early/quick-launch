import AppKit
import QuartzCore
import QuickLaunchCore
@_spi(Testing) import QuickLaunchUI

func expect(_ value: @autoclosure () -> Bool, _ message: String) {
    guard value() else { fputs("FAIL: \(message)\n", stderr); exit(1) }
    print("PASS: \(message)")
}
func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
func captureEvidence(_ view: NSView, name: String) {
    guard let directory = ProcessInfo.processInfo.environment["QUICK_LAUNCH_EVIDENCE_DIR"],
          let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
    view.cacheDisplay(in: view.bounds, to: bitmap)
    let destination = URL(fileURLWithPath: directory).appendingPathComponent(name)
    try! FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
    try! bitmap.representation(using: .png, properties: [:])!.write(to: destination)
}
let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
let launcher = LauncherController()
let content = launcher.panel.contentView!
let views = descendants(content)
expect(views.contains(where: { $0 is NSScrollView }), "results have a native scroll view on initial construction")
let table = views.compactMap { $0 as? NSTableView }.first!
let deadline = Date().addingTimeInterval(10)
while table.numberOfRows == 0 && Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.01)) }
content.layoutSubtreeIfNeeded()
captureEvidence(content, name: "apps-hidden-native.png")
expect(table.numberOfRows > 8, "first empty query retains apps beyond the visible eight")
let scroll = table.enclosingScrollView!
let initialY = scroll.contentView.bounds.minY
let header = views.compactMap { $0 as? NSTextField }.first { $0.placeholderString == "Search applications" }!
let headerFrame = header.frame
let panelFrame = launcher.panel.frame
let last = table.numberOfRows - 1
table.scrollRowToVisible(last)
expect(scroll.contentView.bounds.minY > initialY, "native scrolling reaches later results without typing first")
expect(table.rows(in: scroll.documentVisibleRect).contains(last), "last result is inside the scroll viewport")
expect(header.frame == headerFrame && launcher.panel.frame == panelFrame, "scrolling leaves header and panel geometry fixed")

let editor = NSTextView()
for _ in 0..<10 {
    _ = launcher.control(header, textView: editor, doCommandBy: #selector(NSResponder.moveDown(_:)))
}
expect(table.selectedRow == 10, "keyboard selection reaches beyond the first visible page")
expect(NSLocationInRange(table.selectedRow, table.rows(in: scroll.documentVisibleRect)), "keyboard selection scrolls into view")
let dragSurfaces = descendants(content).compactMap { $0 as? DragSurface }
expect(dragSurfaces.count == 2, "search icon and empty query have explicit drag surfaces")
let emptyDrag = dragSurfaces.max { $0.frame.width < $1.frame.width }!
expect(!emptyDrag.isHidden, "empty search placeholder is a drag target on first opening")
expect(launcher.panel.makeFirstResponder(header), "search field accepts initial keyboard focus")
expect(content.hitTest(NSPoint(x: header.frame.midX, y: header.frame.midY)) === emptyDrag, "empty-field mouse hits reach the drag surface")
header.stringValue = "term"
launcher.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: header))
expect(emptyDrag.isHidden, "non-empty query keeps the drag overlay out of text selection")
expect(table.numberOfRows > 0 && table.numberOfRows < 8, "query filtering still updates the native list")
expect(table.selectedRow == 0 && scroll.contentView.bounds.minY == 0, "new query resets selection and scroll to top")
_ = launcher.control(header, textView: editor, doCommandBy: #selector(NSResponder.insertTab(_:)))
expect(header.stringValue == "Terminal", "Tab still completes the selected result")
editor.string = header.stringValue
editor.setSelectedRange(NSRange(location: (editor.string as NSString).length, length: 0))
_ = launcher.control(header, textView: editor, doCommandBy: #selector(NSResponder.insertTab(_:)))
expect((launcher.panel.firstResponder as? ProjectShortcutButton)?.tag == 0, "Tab after a fully completed app name enters project logos")
header.stringValue = ""
launcher.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: header))
expect(!emptyDrag.isHidden && table.numberOfRows > 8, "clearing search restores drag target and full scrollable list")

final class DragSpyWindow: NSWindow {
    var dragEvent: NSEvent?
    override func performDrag(with event: NSEvent) { dragEvent = event }
}
let spy = DragSpyWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 80), styleMask: [.borderless], backing: .buffered, defer: false)
let drag = DragSurface(frame: NSRect(x: 0, y: 0, width: 200, height: 80))
spy.contentView!.addSubview(drag)
let event = NSEvent.mouseEvent(with: .leftMouseDown, location: NSPoint(x: 20, y: 20), modifierFlags: [], timestamp: 0, windowNumber: spy.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1)!
drag.mouseDown(with: event)
expect(spy.dragEvent === event, "drag surface hands the original mouse-down event to native window dragging")
print("PASS: native interaction checks complete")

let dismissPanel = SearchPanel(contentRect: NSRect(x: 0, y: 0, width: 200, height: 100), styleMask: [.borderless], backing: .buffered, defer: false)
let focusedTable = NSTableView(frame: dismissPanel.contentView!.bounds)
dismissPanel.contentView!.addSubview(focusedTable)
_ = dismissPanel.makeFirstResponder(focusedTable)
var escapeDismissals = 0
dismissPanel.onDismiss = { escapeDismissals += 1 }
let escape = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: dismissPanel.windowNumber, context: nil, characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53)!
dismissPanel.sendEvent(escape)
expect(escapeDismissals == 1, "Escape dismisses even when the result table has focus")
let focusedField = NSTextField(frame: NSRect(x: 0, y: 0, width: 100, height: 30))
dismissPanel.contentView!.addSubview(focusedField)
_ = dismissPanel.makeFirstResponder(focusedField)
dismissPanel.sendEvent(escape)
expect(escapeDismissals == 2, "Escape dismissal is independent of focused control")
let plan = WindowTransitionPlan(window: CGRect(x: 0, y: 100, width: 800, height: 600), icon: CGRect(x: 900, y: 750, width: 32, height: 32))!
expect(plan.overlay.contains(CGRect(x: 0, y: 100, width: 800, height: 600)) && plan.overlay.contains(CGRect(x: 900, y: 750, width: 32, height: 32)), "animation overlay contains both actual window and clicked logo")
expect(plan.expanded.width == 800 && plan.collapsed.width == 32, "window animation preserves the requested endpoints")
expect(WindowTransitionPlan(window: .zero, icon: .zero) == nil, "invalid snapshot geometry skips the animation")

var injectedLaunches = 0
var transitionCompletions = 0
let cancelledTransition = ProjectTransitionTask.start(completion: { transitionCompletions += 1 }) {
    injectedLaunches += 1
}
cancelledTransition.cancel()
let cancellationDeadline = Date().addingTimeInterval(2)
while transitionCompletions == 0 && Date() < cancellationDeadline {
    RunLoop.current.run(until: Date().addingTimeInterval(0.01))
}
expect(injectedLaunches == 0, "cancellation before the scheduled transition prevents app launch")
expect(transitionCompletions == 1, "cancelled transition still releases its busy state exactly once")

let projectLogos = descendants(content).compactMap { $0 as? ProjectShortcutButton }.filter { $0.tag >= 0 }.sorted { $0.tag < $1.tag }
expect(projectLogos.count >= 2, "installed project logos accept keyboard focus")
editor.string = "A🚀"
editor.setSelectedRange(NSRange(location: 1, length: 0))
expect(!launcher.control(header, textView: editor, doCommandBy: #selector(NSResponder.moveRight(_:))), "Right Arrow inside search text keeps normal caret movement")
editor.setSelectedRange(NSRange(location: 1, length: 2))
expect(!launcher.control(header, textView: editor, doCommandBy: #selector(NSResponder.moveRight(_:))), "Right Arrow with selected text keeps native selection behavior")
editor.setSelectedRange(NSRange(location: 3, length: 0))
expect(launcher.control(header, textView: editor, doCommandBy: #selector(NSResponder.moveRight(_:))) && launcher.panel.firstResponder === projectLogos[0], "Right Arrow at the UTF-16 text end focuses the first project logo")
func projectKey(_ code: UInt16, modifiers: NSEvent.ModifierFlags = []) -> NSEvent {
    NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: 0, windowNumber: launcher.panel.windowNumber, context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: code)!
}
projectLogos[0].keyDown(with: projectKey(124))
expect(launcher.panel.firstResponder === projectLogos[1], "Right Arrow moves to the next project logo")
projectLogos[1].keyDown(with: projectKey(123))
expect(launcher.panel.firstResponder === projectLogos[0], "Left Arrow moves to the previous project logo")
projectLogos[0].keyDown(with: projectKey(48))
expect(launcher.panel.firstResponder === projectLogos[1], "Tab traverses project logos")
projectLogos[1].keyDown(with: projectKey(48, modifiers: .shift))
expect(launcher.panel.firstResponder === projectLogos[0], "Shift-Tab traverses project logos backwards")
projectLogos[0].keyDown(with: projectKey(123))
expect(launcher.panel.firstResponder !== projectLogos[0] && header.currentEditor()?.selectedRange == NSRange(location: 0, length: 0), "Left Arrow from the first logo restores search focus at the text end")
_ = launcher.panel.makeFirstResponder(projectLogos.last!)
projectLogos.last!.keyDown(with: projectKey(124))
let settingsButton = descendants(content).compactMap { $0 as? ProjectShortcutButton }.first { $0.tag == -1 }!
expect(launcher.panel.firstResponder === settingsButton, "Right Arrow after the last logo reaches settings")
_ = launcher.panel.makeFirstResponder(projectLogos.last!)
projectLogos.last!.keyDown(with: projectKey(48))
expect(launcher.panel.firstResponder === settingsButton, "Tab after the last project reaches settings")
settingsButton.keyDown(with: projectKey(48))
expect(launcher.panel.firstResponder !== settingsButton, "Tab after settings returns to search")
final class ProjectActionSpy: NSObject {
    var activations = 0
    @objc func activate(_ sender: Any?) { activations += 1 }
}
let actionSpy = ProjectActionSpy()
let actionButton = ProjectShortcutButton(title: "", target: actionSpy, action: #selector(ProjectActionSpy.activate(_:)))
actionButton.keyDown(with: projectKey(36))
actionButton.keyDown(with: projectKey(49))
expect(actionSpy.activations == 2, "Return and Space activate the focused project without using any real application")

_ = launcher.panel.makeFirstResponder(projectLogos[1])
let focusedProjectName = projectLogos[1].toolTip
launcher.refreshIndex(force: true)
let refreshDeadline = Date().addingTimeInterval(10)
while projectLogos[1].superview != nil && Date() < refreshDeadline {
    RunLoop.current.run(until: Date().addingTimeInterval(0.01))
}
expect(projectLogos[1].superview == nil && (launcher.panel.firstResponder as? ProjectShortcutButton)?.toolTip == focusedProjectName,
       "background index refresh preserves keyboard focus on the same project")
let refreshedLogo = launcher.panel.firstResponder as! ProjectShortcutButton
refreshedLogo.keyDown(with: projectKey(123))
expect((launcher.panel.firstResponder as? ProjectShortcutButton)?.tag == 0, "logo arrow navigation continues after background refresh")

let faces = launcher.panel.contentView as! LauncherFaces
let reverseBack = descendants(faces.reverse).compactMap { $0 as? ProjectShortcutButton }.first { $0.tag == -2 }!
expect(header.font?.pointSize == 23 && dragSurfaces.map(\.frame.width).min() == 26, "search text and magnifying glass are slightly smaller")
let rightmostLogo = descendants(faces.front).compactMap { $0 as? ProjectShortcutButton }.filter { $0.tag >= 0 }.max { $0.tag < $1.tag }!
let divider = descendants(faces.front).compactMap { $0 as? NSBox }.first { $0.boxType == .separator }!
expect(rightmostLogo.convert(rightmostLogo.bounds, to: content).maxX < divider.convert(divider.bounds, to: content).minX && divider.frame.maxX < settingsButton.frame.minX,
       "divider separates project logos from settings without changing their order")
header.stringValue = "zzzzzzzzzz"
launcher.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: header))
content.layoutSubtreeIfNeeded()
let compactSearchFrame = launcher.panel.frame
captureEvidence(faces, name: "search-hidden-native.png")
settingsButton.performClick(nil)
content.layoutSubtreeIfNeeded()
captureEvidence(faces, name: "settings-hidden-native.png")
expect(faces.showingBack && faces.front.isHidden && !faces.reverse.isHidden, "settings reveals the reverse face without foregrounding the panel")
expect(launcher.panel.frame == compactSearchFrame, "revealing settings preserves the window bounds")
let swatches = descendants(faces.reverse).compactMap { $0 as? ProjectShortcutButton }.filter { $0.tag <= -10 }
expect(swatches.count == HighlightColor.allCases.count && swatches.allSatisfy { faces.reverse.bounds.contains($0.convert($0.bounds, to: faces.reverse)) }, "highlight controls fit even the smallest search window")
expect(launcher.panel.firstResponder === reverseBack, "reverse face starts with keyboard focus on Back to search")
reverseBack.performClick(nil)
expect(!faces.showingBack && faces.reverse.isHidden && header.stringValue == "zzzzzzzzzz", "flipping back retains the current search query")

faces.setShowingBack(true, animated: true, reduceMotion: false)
let rotation = faces.front.layer?.animation(forKey: "launcher-face") as? CAKeyframeAnimation
let finalRotation = (rotation?.values?.last as? NSValue)?.caTransform3DValue
expect(rotation?.keyPath == "transform" && rotation?.duration == 0.28 && abs((finalRotation?.m11 ?? 0) + 1) < 0.0001, "normal motion uses a 180-degree layer rotation")
let panelCenter = CGPoint(x: faces.bounds.midX, y: faces.bounds.midY)
expect((rotation?.values as? [NSValue])?.allSatisfy { value in
    let transform = value.caTransform3DValue
    let x = panelCenter.x * transform.m11 + panelCenter.y * transform.m21 + transform.m41
    let y = panelCenter.x * transform.m12 + panelCenter.y * transform.m22 + transform.m42
    let z = panelCenter.x * transform.m13 + panelCenter.y * transform.m23 + transform.m43
    return abs(x - panelCenter.x) < 0.0001 && abs(y - panelCenter.y) < 0.0001 && abs(z) < 0.0001
} == true, "every intermediate flip transform keeps the panel center fixed")
faces.setShowingBack(false, animated: false)
let settleDeadline = Date().addingTimeInterval(0.4)
while Date() < settleDeadline { RunLoop.current.run(until: Date().addingTimeInterval(0.01)) }
expect(!faces.showingBack && !faces.front.isHidden && faces.reverse.isHidden, "cancelled flip completions cannot reveal a stale face")
faces.setShowingBack(true, animated: true, reduceMotion: true)
let fade = faces.front.layer?.animation(forKey: "launcher-face") as? CABasicAnimation
expect(fade?.keyPath == "opacity" && fade?.duration == 0.08 && CATransform3DIsIdentity(faces.front.layer!.transform), "Reduce Motion substitutes a short fade for rotation")
faces.setShowingBack(false, animated: false)

let appearanceSuite = "QuickLaunchAppearanceChecks.\(UUID().uuidString)"
let appearanceDefaults = UserDefaults(suiteName: appearanceSuite)!
defer { appearanceDefaults.removePersistentDomain(forName: appearanceSuite) }
let appearance = LauncherAppearance(defaults: appearanceDefaults)
expect(appearance.highlight == .system, "highlight defaults to the macOS accent")
appearance.choose(.purple)
expect(LauncherAppearance(defaults: appearanceDefaults).highlight == .purple, "chosen highlight persists between launches")

_ = launcher.panel.makeFirstResponder(header)
editor.string = header.stringValue
editor.setSelectedRange(NSRange(location: (editor.string as NSString).length, length: 0))
_ = launcher.control(header, textView: editor, doCommandBy: #selector(NSResponder.insertTab(_:)))
expect((launcher.panel.firstResponder as? ProjectShortcutButton)?.tag == 0, "Tab at search end with no results enters project logos")
_ = launcher.panel.makeFirstResponder(header)
editor.setSelectedRange(NSRange(location: 1, length: 0))
_ = launcher.control(header, textView: editor, doCommandBy: #selector(NSResponder.insertTab(_:)))
expect(!(launcher.panel.firstResponder is ProjectShortcutButton), "Tab does not leave unmatched text when the caret is inside it")
editor.setSelectedRange(NSRange(location: 0, length: 1))
_ = launcher.control(header, textView: editor, doCommandBy: #selector(NSResponder.insertTab(_:)))
expect(!(launcher.panel.firstResponder is ProjectShortcutButton), "Tab does not leave unmatched selected text")
content.layoutSubtreeIfNeeded()
let iconSurface = dragSurfaces.min { $0.frame.width < $1.frame.width }!
expect(abs(iconSurface.frame.midY - header.frame.midY) < 0.5, "search input and magnifying glass share their vertical center")
header.stringValue = "Terminal"
launcher.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: header))
content.layoutSubtreeIfNeeded()
captureEvidence(content, name: "typed-search-hidden-native.png")

let recorder = ShortcutRecorder(frame: NSRect(x: 0, y: 0, width: 180, height: 32))
dismissPanel.contentView!.addSubview(recorder)
recorder.performClick(nil)
_ = dismissPanel.makeFirstResponder(recorder)
dismissPanel.sendEvent(escape)
expect(!recorder.isRecording && escapeDismissals == 2, "Escape cancels shortcut recording without dismissing settings")
var recordedShortcut: LauncherHotKey?
recorder.onChange = { value in recordedShortcut = value; return "Already in use" }
recorder.performClick(nil)
let commandK = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command, timestamp: 0, windowNumber: dismissPanel.windowNumber, context: nil, characters: "k", charactersIgnoringModifiers: "k", isARepeat: false, keyCode: 40)!
recorder.keyDown(with: commandK)
expect(recorder.isRecording && recordedShortcut?.keyCode == 40, "shortcut conflict leaves recording active for another choice")
recorder.onChange = { value in recordedShortcut = value; return nil }
recorder.keyDown(with: commandK)
expect(!recorder.isRecording && recorder.title == "⌘K", "accepted shortcut is displayed after recording")
let configuredFolders = descendants(faces.reverse).compactMap { $0 as? NSPopUpButton }.first!
expect(configuredFolders.numberOfItems == IndexLocation.standard.count, "settings lists the Applications-only default folders")
expect(descendants(faces.reverse).contains { ($0 as? NSButton)?.title == "Spotlight services…" }, "settings exposes the deliberate Spotlight workflow without starting it")
header.stringValue = ""
launcher.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: header))
settingsButton.performClick(nil)
content.layoutSubtreeIfNeeded()
captureEvidence(content, name: "configuration-hidden-native.png")
reverseBack.performClick(nil)

let manyFiles = (0..<3_000).map { Application(name: "Document \($0).txt", url: URL(fileURLWithPath: "/Fixture/Document \($0).txt"), kind: .file) }
launcher.replaceSearchInventory(manyFiles)
header.stringValue = "Document 1"
launcher.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: header))
header.stringValue = "Document 2999.txt"
launcher.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: header))
let searchDeadline = Date().addingTimeInterval(5)
while Date() < searchDeadline {
    RunLoop.current.run(until: Date().addingTimeInterval(0.01))
    let cell = table.view(atColumn: 0, row: 0, makeIfNecessary: true) as? NSTableCellView
    if table.numberOfRows == 1 && cell?.textField?.stringValue == "Document 2999.txt" { break }
}
let fileResult = table.view(atColumn: 0, row: 0, makeIfNecessary: true) as? NSTableCellView
expect(table.numberOfRows == 1 && fileResult?.textField?.stringValue == "Document 2999.txt", "large-folder searches publish only the latest query")
expect(fileResult?.toolTip == "/Fixture/Document 2999.txt", "file results expose their containing path for disambiguation")

let spotlightFixture = spotlightServiceEvidence([
    SpotlightService(label: "com.apple.metadata.mds", domain: "system", loaded: true, disabled: false),
    SpotlightService(label: "com.apple.mdworker.shared", domain: "gui/502", loaded: false, disabled: true),
    SpotlightService(label: "com.apple.corespotlightd", domain: "gui/502", loaded: true, disabled: nil)
])
let reviewButtons = descendants(spotlightFixture.1).compactMap { $0 as? NSButton }
expect(reviewButtons.contains { $0.title == "Disable selected…" } && reviewButtons.contains { $0.title == "Enable selected…" }, "Spotlight review has explicit disable and enable actions")
withExtendedLifetime(spotlightFixture.0) { captureEvidence(spotlightFixture.1, name: "spotlight-review-fixture-hidden-native.png") }
