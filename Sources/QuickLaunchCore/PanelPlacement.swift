import Foundation
import CoreGraphics

public enum PanelPlacement {
    public static func fitted(_ frame: CGRect, in visibleFrame: CGRect) -> CGRect {
        let area = visibleFrame.insetBy(dx: 12, dy: 12)
        let width = min(frame.width, max(1, area.width))
        let height = min(frame.height, max(1, area.height))
        return CGRect(x: max(area.minX, min(frame.minX, area.maxX - width)),
                      y: max(area.minY, min(frame.minY, area.maxY - height)), width: width, height: height)
    }

    public static func resultLimit(in visibleFrame: CGRect) -> Int {
        max(1, min(8, Int((visibleFrame.height - 24 - 86) / 58)))
    }
}
