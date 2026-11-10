import Foundation

public struct CommandResult {
    public let status: Int32
    public let output: String
    public let error: String
    public init(_ status: Int32, _ output: String = "", _ error: String = "") { self.status = status; self.output = output; self.error = error }
}

public struct SpotlightService: Codable, Equatable {
    public let label: String
    public let domain: String
    public let loaded: Bool
    public let disabled: Bool?
    public var target: String { domain + "/" + label }
    public var state: String {
        if disabled == true { return loaded ? "Disabled, still loaded" : "Disabled, stopped" }
        return loaded ? "Loaded" : (disabled == false ? "Enabled, not loaded" : "Policy unknown")
    }
    public init(label: String, domain: String, loaded: Bool, disabled: Bool?) { self.label = label; self.domain = domain; self.loaded = loaded; self.disabled = disabled }
}

public struct SpotlightChange: Codable {
    public let service: SpotlightService
    public let disabled: Bool
    public let succeeded: Bool
    public let detail: String
}

public struct SpotlightRequest: Codable {
    public let services: [SpotlightService]
    public let disabled: Bool
    public init(services: [SpotlightService], disabled: Bool) { self.services = services; self.disabled = disabled }
    public var isValid: Bool { !services.isEmpty && services.count <= 128 && services.allSatisfy { SpotlightServices.isValidTarget($0) } }
}

public enum SpotlightServices {
    public typealias Runner = ([String]) -> CommandResult
    // Narrow launchd families from macos-service-manager, not general filesystem services.
    public static func includes(_ label: String) -> Bool {
        let names: Set<String> = ["com.apple.Spotlight", "com.apple.mds", "com.apple.metadata.mds", "com.apple.corespotlightd", "com.apple.corespotlightservice", "com.apple.managedcorespotlightd", "com.apple.spotlightknowledged", "com.apple.searchtoold", "com.apple.suggestd", "com.apple.parsecd", "com.apple.msrpc.mdssvc", "com.apple.diagnosticextensions.osx.spotlight.helper"]
        return names.contains(label) || ["com.apple.mdworker.", "com.apple.metadata.mds.", "com.apple.spotlightknowledged."].contains { label.hasPrefix($0) }
    }
    public static func isValidTarget(_ service: SpotlightService) -> Bool {
        includes(service.label) && service.label.range(of: "^[A-Za-z0-9._-]{1,180}$", options: .regularExpression) != nil &&
        service.domain.range(of: "^(system|gui/[0-9]{1,10}|user/[0-9]{1,10})$", options: .regularExpression) != nil
    }
    private static func matches(_ pattern: String, _ text: String) -> [[String]] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines]) else { return [] }
        let ns = text as NSString
        return regex.matches(in: text, range: NSRange(location: 0, length: ns.length)).map { match in
            (0..<match.numberOfRanges).map { match.range(at: $0).location == NSNotFound ? "" : ns.substring(with: match.range(at: $0)) }
        }
    }
    public static func overrides(_ output: String) -> [String: Bool] {
        Dictionary(matches("\"([^\"\\n]+)\"\\s*=>\\s*(true|false|enabled|disabled)", output).map { ($0[1], $0[2] == "true" || $0[2] == "disabled") }, uniquingKeysWith: { _, last in last })
    }
    public static func loadedLabels(_ output: String) -> Set<String> {
        guard let block = output.range(of: "(?ms)^\\s*services = \\{\\s*$.*?^\\s*\\}", options: .regularExpression) else { return [] }
        return Set(matches("^\\s*(?:[0-9]+|-)\\s+[-0-9]+\\s+(\\S+)\\s*$", String(output[block])).map { $0[1] })
    }
    public static func discover(uid: UInt32, run: Runner) -> (services: [SpotlightService], errors: [String]) {
        var services: [SpotlightService] = []
        var errors: [String] = []
        for domain in ["system", "gui/\(uid)", "user/\(uid)"] {
            let jobs = run(["print", domain])
            let policy = run(["print-disabled", domain])
            if jobs.status != 0 { errors.append("\(domain): \(jobs.error)") }
            if policy.status != 0 { errors.append("\(domain) policy: \(policy.error)") }
            let loaded = jobs.status == 0 ? loadedLabels(jobs.output) : []
            let disabled = policy.status == 0 ? overrides(policy.output) : [:]
            for label in loaded.union(disabled.keys).sorted() where includes(label) {
                services.append(SpotlightService(label: label, domain: domain, loaded: loaded.contains(label), disabled: disabled[label]))
            }
        }
        return (services, errors)
    }
    public static func apply(_ request: SpotlightRequest, run: Runner) -> [SpotlightChange] {
        guard request.isValid else { return [] }
        return request.services.map { service in
            var before = service
            func result(_ ok: Bool, _ message: String) -> SpotlightChange { SpotlightChange(service: before, disabled: request.disabled, succeeded: ok, detail: message) }
            let originalPolicy = run(["print-disabled", service.domain])
            guard originalPolicy.status == 0 else { return result(false, "Cannot read original policy. " + originalPolicy.error) }
            let originalJob = run(["print", service.target])
            let missing = originalJob.status == 113 && originalJob.error.contains("Could not find service") && originalJob.error.contains(service.label)
            guard originalJob.status == 0 || missing else { return result(false, "Cannot verify the original job. " + originalJob.error) }
            before = SpotlightService(label: service.label, domain: service.domain, loaded: originalJob.status == 0, disabled: overrides(originalPolicy.output)[service.label])
            let action = run([request.disabled ? "disable" : "enable", service.target])
            guard action.status == 0 else { return result(false, action.error.isEmpty ? action.output : action.error) }
            let stop = request.disabled ? run(["bootout", service.target]) : nil
            let policy = run(["print-disabled", service.domain])
            guard policy.status == 0, overrides(policy.output)[service.label] == request.disabled else { return result(false, "Could not verify launch policy. " + policy.error) }
            if request.disabled {
                let job = run(["print", service.target])
                guard job.status == 113 && job.error.contains("Could not find service") && job.error.contains(service.label) else {
                    return result(false, "Disable policy saved, but stopping was not verified. " + (job.status == 0 ? "Job is still loaded. " : job.error) + (stop?.error ?? ""))
                }
            }
            return result(true, request.disabled ? "Disabled and stopped" : "Enabled; can load again at login or reboot")
        }
    }
}
