import AppKit

public enum HighlightColor: String, CaseIterable {
    case system, blue, purple, pink, orange, green
    public var title: String { self == .system ? "System accent" : rawValue.capitalized }
    public var color: NSColor {
        switch self {
        case .system: return .controlAccentColor
        case .blue: return .systemBlue
        case .purple: return .systemPurple
        case .pink: return .systemPink
        case .orange: return .systemOrange
        case .green: return .systemGreen
        }
    }
}

public final class LauncherAppearance {
    public static let shared = LauncherAppearance(defaults: .standard)
    private let defaults: UserDefaults
    public private(set) var highlight: HighlightColor
    public init(defaults: UserDefaults) {
        self.defaults = defaults
        highlight = HighlightColor(rawValue: defaults.string(forKey: "highlightColor") ?? "") ?? .system
    }
    public func choose(_ color: HighlightColor) {
        highlight = color
        defaults.set(color.rawValue, forKey: "highlightColor")
    }
}
