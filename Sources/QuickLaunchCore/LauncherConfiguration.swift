import Foundation

public struct LauncherHotKey: Codable, Equatable {
    public var keyCode: UInt32
    /// Command=1, Option=2, Control=4, Shift=8.
    public var modifiers: UInt32
    public var key: String
    public init(keyCode: UInt32, modifiers: UInt32, key: String) { self.keyCode = keyCode; self.modifiers = modifiers; self.key = key }
    public static let standard = Self(keyCode: 49, modifiers: 1, key: "Space")
    public var isValid: Bool { keyCode < 128 && modifiers & 7 != 0 && modifiers & ~15 == 0 && !key.isEmpty && key.count <= 16 && key.unicodeScalars.allSatisfy { !CharacterSet.controlCharacters.contains($0) } }
    public var title: String {
        [(4, "⌃"), (2, "⌥"), (8, "⇧"), (1, "⌘")].compactMap { modifiers & UInt32($0.0) != 0 ? $0.1 : nil }.joined() + key
    }
}

public final class IndexScanCancellation {
    private let lock = NSLock()
    private var cancelled = false
    public init() {}
    public var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return cancelled }
    public func cancel() { lock.lock(); cancelled = true; lock.unlock() }
}

public struct IndexLocation: Codable, Equatable {
    public var path: String
    public var includesFiles: Bool
    public init(path: String, includesFiles: Bool) { self.path = URL(fileURLWithPath: path).standardizedFileURL.path; self.includesFiles = includesFiles }
    public static var standard: [Self] { ApplicationIndex.standardRoots.map { Self(path: $0.path, includesFiles: false) } }
}

public final class LauncherConfiguration {
    public static let shared = LauncherConfiguration(defaults: .standard)
    private let defaults: UserDefaults
    public private(set) var hotKey: LauncherHotKey
    public private(set) var locations: [IndexLocation]
    public init(defaults: UserDefaults) {
        self.defaults = defaults
        let savedKey = defaults.data(forKey: "launcherHotKey").flatMap { try? JSONDecoder().decode(LauncherHotKey.self, from: $0) }
        hotKey = savedKey?.isValid == true ? savedKey! : .standard
        locations = defaults.data(forKey: "indexLocations").flatMap { try? JSONDecoder().decode([IndexLocation].self, from: $0) } ?? IndexLocation.standard
        locations = Self.normalized(locations)
    }
    public func setHotKey(_ value: LauncherHotKey) {
        guard value.isValid else { return }
        hotKey = value
        defaults.set(try? JSONEncoder().encode(value), forKey: "launcherHotKey")
    }
    public func setLocations(_ values: [IndexLocation]) {
        locations = Self.normalized(values)
        defaults.set(try? JSONEncoder().encode(locations), forKey: "indexLocations")
    }
    private static func normalized(_ values: [IndexLocation]) -> [IndexLocation] {
        var seen = Set<String>()
        return values.filter { $0.path.hasPrefix("/") }.compactMap {
            let item = IndexLocation(path: $0.path, includesFiles: $0.includesFiles)
            return seen.insert(item.path).inserted ? item : nil
        }
    }
}
