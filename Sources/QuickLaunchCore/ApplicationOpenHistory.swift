import Foundation

/// Local launcher usage only; counts are retained when an application is absent.
public final class ApplicationOpenHistory {
    private let defaults: UserDefaults
    private let key = "applicationOpenCounts"
    public private(set) var counts: [String: Int]

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        counts = (defaults.dictionary(forKey: key) as? [String: Int] ?? [:]).filter { $0.value > 0 }
    }

    public func recordOpen(_ application: Application) {
        let path = application.url.standardizedFileURL.path
        let previous = counts[path, default: 0]
        counts[path] = previous == Int.max ? Int.max : previous + 1
        defaults.set(counts, forKey: key)
    }
}
