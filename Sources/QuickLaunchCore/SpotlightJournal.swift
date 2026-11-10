import Foundation
import Darwin

public struct SpotlightJournalRecord: Codable {
    public let phase: String
    public let pid: Int32
    public let service: SpotlightService?
    public let change: SpotlightChange?
    public init(phase: String, pid: Int32, service: SpotlightService? = nil, change: SpotlightChange? = nil) { self.phase = phase; self.pid = pid; self.service = service; self.change = change }
}

public enum SpotlightOperationRecovery {
    public static func shouldWait(wrapperFailed: Bool, deadline: Date, records: [SpotlightJournalRecord], now: Date = Date(), helperRunning: (Int32) -> Bool) -> Bool {
        if records.last?.phase == "complete" { return false }
        if let started = records.first { return helperRunning(started.pid) }
        // The wrapper can exit between spawning the helper and its first fsync.
        // Allow the command deadline plus termination grace before assuming it never began.
        return wrapperFailed && now < deadline.addingTimeInterval(15)
    }
}

/// Privileged writes use a fixed, root-owned directory and an exclusive no-follow file.
/// Journals contain only public launchd labels, domains, policies and result messages.
public final class SpotlightJournal {
    public static let directory = "/Library/Application Support/QuickLaunch/SpotlightReports"
    private let file: FileHandle
    public private(set) var error = ""
    public static func url(_ id: UUID) -> URL { URL(fileURLWithPath: directory).appendingPathComponent(id.uuidString + ".jsonl") }
    public init(id: UUID) throws {
        guard geteuid() == 0 else { throw CocoaError(.fileWriteNoPermission) }
        for path in ["/Library", "/Library/Application Support", "/Library/Application Support/QuickLaunch", Self.directory] {
            if path.hasPrefix("/Library/Application Support/QuickLaunch") {
                if mkdir(path, 0o755) != 0 && errno != EEXIST { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
            }
            var info = stat()
            guard lstat(path, &info) == 0, info.st_uid == 0, info.st_mode & S_IFMT == S_IFDIR, info.st_mode & 0o022 == 0 else { throw CocoaError(.fileWriteNoPermission) }
        }
        let descriptor = open(Self.url(id).path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o644)
        guard descriptor >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        file = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        guard append(phase: "started") else { throw CocoaError(.fileWriteUnknown) }
    }
    @discardableResult public func append(phase: String, service: SpotlightService? = nil, change: SpotlightChange? = nil) -> Bool {
        guard error.isEmpty else { return false }
        do {
            var data = try JSONEncoder().encode(SpotlightJournalRecord(phase: phase, pid: getpid(), service: service, change: change))
            data.append(10)
            try file.write(contentsOf: data)
            try file.synchronize()
            return true
        } catch { self.error = error.localizedDescription; return false }
    }
    public static func read(_ id: UUID) -> [SpotlightJournalRecord] {
        guard let data = try? Data(contentsOf: url(id)) else { return [] }
        return data.split(separator: 10).compactMap { try? JSONDecoder().decode(SpotlightJournalRecord.self, from: Data($0)) }
    }
}
