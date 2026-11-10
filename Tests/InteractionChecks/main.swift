import AppKit
import QuickLaunchCore
import QuickLaunchUI

func expect(_ value: @autoclosure () -> Bool, _ message: String) {
    guard value() else { fputs("FAIL: \(message)\n", stderr); exit(1) }
    print("PASS: \(message)")
}
func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
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

let projectLogos = descendants(content).compactMap { $0 as? ProjectShortcutButton }.sorted { $0.tag < $1.tag }
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
expect(launcher.panel.firstResponder === projectLogos.last!, "Right Arrow at the last logo stays within the project group")
projectLogos.last!.keyDown(with: projectKey(48))
expect(launcher.panel.firstResponder !== projectLogos.last!, "Tab after the last project returns to search")
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
