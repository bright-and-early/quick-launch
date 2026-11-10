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
        NSColor.selectedContentBackgroundColor.withAlphaComponent(0.22).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 9, yRadius: 9).fill()
    }
}

final class ApplicationResultCell: NSTableCellView {
    private let appImage = NSImageView()
    private let nameLabel = NSTextField(labelWithString: "")
    private let pathLabel = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        appImage.imageScaling = .scaleProportionallyUpOrDown
        nameLabel.font = .systemFont(ofSize: 16, weight: .medium)
        nameLabel.lineBreakMode = .byTruncatingTail
        pathLabel.font = .systemFont(ofSize: 11)
        pathLabel.textColor = .secondaryLabelColor
        pathLabel.lineBreakMode = .byTruncatingMiddle
        for view in [appImage, nameLabel, pathLabel] {
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
            nameLabel.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            nameLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            pathLabel.leadingAnchor.constraint(equalTo: nameLabel.leadingAnchor),
            pathLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 3),
            pathLabel.trailingAnchor.constraint(equalTo: nameLabel.trailingAnchor)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(_ application: Application, icon: NSImage) {
        nameLabel.stringValue = application.name
        pathLabel.stringValue = application.url.deletingLastPathComponent().path.replacingOccurrences(of: NSHomeDirectory(), with: "~")
        appImage.image = icon
    }
}
