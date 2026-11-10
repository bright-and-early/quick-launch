import Foundation

public struct Application: Equatable, Sendable {
    public let name: String
    public let url: URL
    public let searchName: String
    public let initials: String

    public init(name: String, url: URL) {
        self.name = name
        self.url = url
        self.searchName = AppSearch.normalize(name)
        self.initials = self.searchName.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).compactMap(\.first).map(String.init).joined()
    }
}

public enum ApplicationIndex {
    public static var standardRoots: [URL] {
        [URL(fileURLWithPath: "/Applications"), URL(fileURLWithPath: "/System/Applications"),
         FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications")]
    }

    public static func scan(roots: [URL] = standardRoots) -> [Application] {
        let manager = FileManager.default
        var seen = Set<String>()
        var apps: [Application] = []
        for root in roots {
            let root = root.standardizedFileURL
            guard let enumerator = manager.enumerator(at: root, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
                options: [.skipsHiddenFiles], errorHandler: { _, _ in true }) else { continue }
            for case let url as URL in enumerator {
                let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
                if values?.isSymbolicLink == true {
                    enumerator.skipDescendants()
                    // Safari is an app link into the sealed system Cryptex. Index
                    // the link itself, never enumerate its destination directory.
                    guard url.pathExtension.lowercased() == "app",
                          (try? url.resolvingSymlinksInPath().resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true else { continue }
                } else if values?.isDirectory != true { continue }
                if url.pathExtension.lowercased() == "app" {
                    enumerator.skipDescendants()
                    guard seen.insert(url.resolvingSymlinksInPath().standardizedFileURL.path).inserted else { continue }
                    let bundle = Bundle(url: url)
                    let name = (bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
                        ?? (bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String)
                        ?? url.deletingPathExtension().lastPathComponent
                    apps.append(Application(name: name, url: url))
                } else if url.pathExtension.lowercased() == "bundle" || url.pathExtension.lowercased() == "framework" {
                    enumerator.skipDescendants()
                }
            }
        }
        return apps.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}
