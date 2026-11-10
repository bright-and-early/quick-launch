import Foundation
import CoreGraphics

public enum ProjectToggleAction: Equatable {
    case launch, hide, show
    public static func decide(isRunning: Bool, isHidden: Bool, wasFrontmost: Bool) -> Self {
        if !isRunning { return .launch }
        return !isHidden && wasFrontmost ? .hide : .show
    }
}

public enum LauncherDismissal {
    public static func shouldDismiss(click: CGPoint, panel: CGRect, isVisible: Bool) -> Bool {
        isVisible && !panel.contains(click)
    }
}

public struct WindowTransitionPlan {
    public let overlay: CGRect
    public let expanded: CGRect
    public let collapsed: CGRect
    public init?(window: CGRect, icon: CGRect) {
        guard [window.minX, window.minY, window.width, window.height, icon.minX, icon.minY, icon.width, icon.height].allSatisfy(\.isFinite),
              window.width > 0, window.height > 0, icon.width > 0, icon.height > 0 else { return nil }
        overlay = window.union(icon).insetBy(dx: -12, dy: -12)
        expanded = window.offsetBy(dx: -overlay.minX, dy: -overlay.minY)
        collapsed = icon.offsetBy(dx: -overlay.minX, dy: -overlay.minY)
    }
}
