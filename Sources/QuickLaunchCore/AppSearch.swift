import Foundation

public enum AppSearch {
    public static func normalize(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    public static func results(for query: String, in apps: [Application], limit: Int = 8, openCounts: [String: Int] = [:]) -> [Application] {
        guard limit > 0 else { return [] }
        let query = normalize(query)
        return apps.compactMap { app -> (Application, Int, Int)? in
            guard let score = score(query, app) else { return nil }
            return (app, score, openCounts[app.url.standardizedFileURL.path, default: 0])
        }.sorted {
            if $0.1 != $1.1 { return $0.1 < $1.1 }
            if $0.2 != $1.2 { return $0.2 > $1.2 }
            if $0.0.searchName != $1.0.searchName { return $0.0.searchName < $1.0.searchName }
            return $0.0.url.path < $1.0.url.path
        }.prefix(limit).map(\.0)
    }

    private static func score(_ query: String, _ app: Application) -> Int? {
        if query.isEmpty { return 0 }
        let name = app.searchName
        if name == query { return 0 }
        if name.hasPrefix(query) { return 100 + name.count - query.count }
        if app.initials == query { return 200 + name.count }
        let words = name.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
        if words.contains(where: { $0.hasPrefix(query) }) { return 300 + name.count }
        if let range = name.range(of: query) {
            return 400 + name.distance(from: name.startIndex, to: range.lowerBound) + name.count
        }
        // Ordered subsequence gives short abbreviations useful matches without edit-distance work.
        var remaining = query.makeIterator()
        var wanted = remaining.next()
        var first = -1
        var last = 0
        for (offset, char) in name.enumerated() where wanted != nil {
            if char == wanted {
                if first < 0 { first = offset }
                last = offset
                wanted = remaining.next()
            }
        }
        guard wanted == nil else { return nil }
        return 600 + (last - first + 1 - query.count) * 4 + first + name.count
    }
}
