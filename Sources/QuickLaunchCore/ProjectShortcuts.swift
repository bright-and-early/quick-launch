import Foundation

public enum ProjectShortcuts {
    /// Pinned installed project apps; discovery still comes from the existing app-only index.
    public static func applications(in inventory: [Application],
                                    directory: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications")) -> [Application] {
        ["AppLab", "Atlas", "Gimme Job", "Matterlab", "Menagerie"].compactMap { name in
            let path = directory.appendingPathComponent("\(name).app").standardizedFileURL
            return inventory.first { $0.url.standardizedFileURL == path }
        }
    }
}
