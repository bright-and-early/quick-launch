import AppKit
import QuickLaunchCore

/// An explicit native drag target, rather than relying on small gaps between controls.
public final class DragSurface: NSView {
    weak var focusField: NSTextField?
    public override var mouseDownCanMoveWindow: Bool { true }
    public override func mouseDown(with event: NSEvent) {
        if let focusField = focusField { window?.makeFirstResponder(focusField) }
        window?.performDrag(with: event)
    }
}

final class ResultRowView: NSTableRowView {
    override func drawSelection(in dirtyRect: NSRect) {
        LauncherAppearance.shared.highlight.color.withAlphaComponent(0.22).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 9, yRadius: 9).fill()
    }
}

final class ApplicationResultCell: NSTableCellView {
    private let appImage = NSImageView()
    private let nameLabel = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        appImage.imageScaling = .scaleProportionallyUpOrDown
        nameLabel.font = .systemFont(ofSize: 16, weight: .medium)
        nameLabel.lineBreakMode = .byTruncatingTail
        for view in [appImage, nameLabel] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        textField = nameLabel
        imageView = appImage
        NSLayoutConstraint.activate([
            appImage.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            appImage.centerYAnchor.constraint(equalTo: centerYAnchor),
            appImage.widthAnchor.constraint(equalToConstant: 40), appImage.heightAnchor.constraint(equalToConstant: 40),
            nameLabel.leadingAnchor.constraint(equalTo: appImage.trailingAnchor, constant: 12),
            nameLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            nameLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(_ application: Application, icon: NSImage) {
        nameLabel.stringValue = application.name
        toolTip = application.kind == .application ? nil : application.url.path
        appImage.image = icon
    }
}
