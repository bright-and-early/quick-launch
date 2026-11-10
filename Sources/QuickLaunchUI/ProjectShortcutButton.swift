import AppKit

public final class ProjectShortcutButton: NSButton {
    var navigate: ((Int, Bool) -> Void)?
    var showsSelection = false { didSet { needsDisplay = true } }
    private var pointerInside = false
    private var pointerTracking: NSTrackingArea?
    public override var acceptsFirstResponder: Bool { true }

    public override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking = pointerTracking { removeTrackingArea(tracking) }
        let tracking = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(tracking)
        pointerTracking = tracking
    }

    public override func mouseEntered(with event: NSEvent) { pointerInside = true; needsDisplay = true }
    public override func mouseExited(with event: NSEvent) { pointerInside = false; needsDisplay = true }
    public override func becomeFirstResponder() -> Bool { needsDisplay = true; return super.becomeFirstResponder() }
    public override func resignFirstResponder() -> Bool { needsDisplay = true; return super.resignFirstResponder() }

    public override func draw(_ dirtyRect: NSRect) {
        let focused = window?.firstResponder === self
        if pointerInside || focused {
            let shape = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 7, yRadius: 7)
            (focused ? LauncherAppearance.shared.highlight.color.withAlphaComponent(0.22) : NSColor.labelColor.withAlphaComponent(0.12)).setFill()
            shape.fill()
            if focused {
                LauncherAppearance.shared.highlight.color.setStroke()
                shape.lineWidth = 2
                shape.stroke()
            }
        }
        super.draw(dirtyRect)
        if showsSelection {
            NSColor.labelColor.withAlphaComponent(0.8).setStroke()
            let ring = NSBezierPath(ovalIn: bounds.insetBy(dx: 1.5, dy: 1.5))
            ring.lineWidth = 1.5
            ring.stroke()
        }
    }

    public override func keyDown(with event: NSEvent) {
        guard event.modifierFlags.intersection([.command, .control, .option]).isEmpty else { super.keyDown(with: event); return }
        switch event.keyCode {
        case 123: navigate?(-1, false)
        case 124: navigate?(1, false)
        case 48: navigate?(event.modifierFlags.contains(.shift) ? -1 : 1, true)
        case 36, 76, 49: performClick(nil)
        default: super.keyDown(with: event)
        }
    }
}
