import AppKit
import QuartzCore

/// Two live native faces share the panel's bounds; the window itself never moves.
public final class LauncherFaces: NSView {
    public let front: NSView
    public let reverse: NSView
    public private(set) var showingBack = false
    public private(set) var isFlipping = false
    public var onSettled: ((Bool) -> Void)?
    private var generation = 0
    public override var acceptsFirstResponder: Bool { true }

    public init(front: NSView, reverse: NSView) {
        self.front = front
        self.reverse = reverse
        super.init(frame: front.frame)
        wantsLayer = true
        var perspective = CATransform3DIdentity
        perspective.m34 = -1 / 1200
        layer?.sublayerTransform = perspective
        for face in [front, reverse] {
            face.wantsLayer = true
            face.layer?.isDoubleSided = false
            face.autoresizingMask = [.width, .height]
            addSubview(face)
        }
        setShowingBack(false, animated: false)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    public override func layout() {
        super.layout()
        front.frame = bounds
        reverse.frame = bounds
    }
    public override func hitTest(_ point: NSPoint) -> NSView? {
        isFlipping ? (bounds.contains(convert(point, from: superview)) ? self : nil) : super.hitTest(point)
    }
    public override func keyDown(with event: NSEvent) {
        if !isFlipping { super.keyDown(with: event) }
    }

    /// AppKit owns backing-layer anchors at (0, 0); compensate within the transform.
    public static func centeredRotation(_ angle: Double, size: NSSize) -> CATransform3D {
        var transform = CATransform3DMakeRotation(angle, 0, 1, 0)
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        transform.m41 = center.x - center.x * transform.m11 - center.y * transform.m21
        transform.m42 = center.y - center.x * transform.m12 - center.y * transform.m22
        transform.m43 = -center.x * transform.m13 - center.y * transform.m23
        return transform
    }

    public func setShowingBack(_ back: Bool, animated: Bool, reduceMotion: Bool? = nil) {
        generation += 1
        let token = generation
        showingBack = back
        isFlipping = animated
        let reduce = reduceMotion ?? NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let frontAngle = back ? Double.pi : 0
        let reverseAngle = back ? 0 : -Double.pi
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        front.layer?.removeAllAnimations()
        reverse.layer?.removeAllAnimations()
        front.isHidden = false
        reverse.isHidden = false
        front.layer?.transform = reduce ? CATransform3DIdentity : Self.centeredRotation(frontAngle, size: bounds.size)
        reverse.layer?.transform = reduce ? CATransform3DIdentity : Self.centeredRotation(reverseAngle, size: bounds.size)
        front.layer?.opacity = reduce && back ? 0 : 1
        reverse.layer?.opacity = reduce && !back ? 0 : 1
        CATransaction.commit()
        guard animated else { settle(back, token: token); return }
        window?.makeFirstResponder(self)
        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak self] in
            DispatchQueue.main.async { self?.settle(back, token: token) }
        }
        for (face, end, start) in [(front, frontAngle, back ? 0 : Double.pi), (reverse, reverseAngle, back ? -Double.pi : 0)] {
            let animation: CAPropertyAnimation
            if reduce {
                let fade = CABasicAnimation(keyPath: "opacity")
                fade.fromValue = face === front ? (back ? 1.0 : 0.0) : (back ? 0.0 : 1.0)
                fade.toValue = face === front ? (back ? 0.0 : 1.0) : (back ? 1.0 : 0.0)
                animation = fade
            } else {
                let turn = CAKeyframeAnimation(keyPath: "transform")
                turn.values = (0...60).map { step in
                    NSValue(caTransform3D: Self.centeredRotation(start + (end - start) * Double(step) / 60, size: bounds.size))
                }
                animation = turn
            }
            animation.duration = reduce ? 0.08 : 0.28
            animation.timingFunction = CAMediaTimingFunction(controlPoints: 0.4, 0, 0.2, 1)
            face.layer?.add(animation, forKey: "launcher-face")
        }
        CATransaction.commit()
    }

    private func settle(_ back: Bool, token: Int) {
        guard generation == token else { return }
        isFlipping = false
        front.isHidden = back
        reverse.isHidden = !back
        onSettled?(back)
    }
}
