import AppKit

public enum HighlightColor: String, CaseIterable {
    case system, blue, indigo, purple, pink, coral, orange, amber, lime, green, teal, cyan
    public var title: String { self == .system ? "System accent" : rawValue.capitalized }
    public var color: NSColor {
        switch self {
        case .system: return .controlAccentColor
        case .blue: return Self.rgb(0x5896FF)
        case .indigo: return Self.rgb(0x8A90F5)
        case .purple: return Self.rgb(0xB38BED)
        case .pink: return Self.rgb(0xEC8DBF)
        case .coral: return Self.rgb(0xF38D87)
        case .orange: return Self.rgb(0xEEA36C)
        case .amber: return Self.rgb(0xDFC16D)
        case .lime: return Self.rgb(0xB2CF7B)
        case .green: return Self.rgb(0x75C79D)
        case .teal: return Self.rgb(0x6BC7BB)
        case .cyan: return Self.rgb(0x77C5DF)
        }
    }
    private static func rgb(_ value: UInt32) -> NSColor {
        NSColor(srgbRed: CGFloat((value >> 16) & 255) / 255,
                green: CGFloat((value >> 8) & 255) / 255,
                blue: CGFloat(value & 255) / 255, alpha: 1)
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
