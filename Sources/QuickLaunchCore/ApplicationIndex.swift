import Foundation

public struct Application: Equatable, Sendable {
    public enum Kind: String, Sendable { case application, file, folder }
    public let name: String
    public let url: URL
    public let searchName: String
    public let initials: String
    public let kind: Kind

    public init(name: String, url: URL, kind: Kind = .application) {
        self.name = name
        self.url = url
        self.kind = kind
        self.searchName = AppSearch.normalize(name)
        self.initials = self.searchName.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).compactMap(\.first).map(String.init).joined()
    }
}

public enum ApplicationIndex {
    public static var standardRoots: [URL] {
        [URL(fileURLWithPath: "/Applications"), URL(fileURLWithPath: "/System/Applications"),
         FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications")]
    }

    public static func scan(roots: [URL] = standardRoots, includeFiles: Bool = false, shouldCancel: () -> Bool = { false }) -> [Application] {
        let manager = FileManager.default
        var seen = Set<String>()
        var apps: [Application] = []
        for root in roots {
            if shouldCancel() { return apps }
            let root = root.standardizedFileURL
            guard let enumerator = manager.enumerator(at: root, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey, .isHiddenKey, .isPackageKey],
                options: [], errorHandler: { _, _ in true }) else { continue }
            for case let url as URL in enumerator {
                if shouldCancel() { return apps }
                let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey, .isHiddenKey, .isPackageKey])
                // macOS marks the Safari.app link hidden. Include application
                // entries, but never traverse hidden folders or staging apps.
                if url.lastPathComponent.hasPrefix(".") || (values?.isHidden == true && url.pathExtension.lowercased() != "app") {
                    enumerator.skipDescendants()
                    continue
                }
                if values?.isSymbolicLink == true {
                    enumerator.skipDescendants()
                    // Safari is an app link into the sealed system Cryptex. Index
                    // the link itself, never enumerate its destination directory.
                    guard url.pathExtension.lowercased() == "app",
                          (try? url.resolvingSymlinksInPath().resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true else { continue }
                } else if values?.isDirectory != true {
                    if includeFiles, seen.insert(url.standardizedFileURL.path).inserted {
                        apps.append(Application(name: url.lastPathComponent, url: url, kind: .file))
                    }
                    continue
                }
                if url.pathExtension.lowercased() == "app" {
                    enumerator.skipDescendants()
                    guard seen.insert(url.resolvingSymlinksInPath().standardizedFileURL.path).inserted else { continue }
                    let bundle = Bundle(url: url)
                    let name = (bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
                        ?? (bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String)
                        ?? url.deletingPathExtension().lastPathComponent
                    apps.append(Application(name: name, url: url))
                } else if values?.isPackage == true || url.pathExtension.lowercased() == "bundle" || url.pathExtension.lowercased() == "framework" {
                    enumerator.skipDescendants()
                    if includeFiles, seen.insert(url.standardizedFileURL.path).inserted {
                        apps.append(Application(name: url.lastPathComponent, url: url, kind: .file))
                    }
                } else if includeFiles, seen.insert(url.standardizedFileURL.path).inserted {
                    apps.append(Application(name: url.lastPathComponent, url: url, kind: .folder))
                }
            }
        }
        return apps.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    public static func scan(locations: [IndexLocation], shouldCancel: () -> Bool = { false }) -> [Application] {
        var seen = Set<String>()
        return locations.flatMap { scan(roots: [URL(fileURLWithPath: $0.path)], includeFiles: $0.includesFiles, shouldCancel: shouldCancel) }
            .filter { seen.insert($0.kind == .application ? $0.url.resolvingSymlinksInPath().standardizedFileURL.path : $0.url.standardizedFileURL.path).inserted }
    }
}
