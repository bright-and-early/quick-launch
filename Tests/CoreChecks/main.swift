import Foundation
import CoreGraphics
import QuickLaunchCore

var checks = 0
func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    checks += 1
    guard condition() else { fputs("FAIL: \(message)\n", stderr); exit(1) }
}
func app(_ name: String) -> Application { Application(name: name, url: URL(fileURLWithPath: "/Applications/\(name).app")) }
let apps = [app("Terminal"), app("Other Terminal"), app("Terminator"), app("Activity Monitor"), app("Google Chrome"), app("Café")]
expect(AppSearch.results(for: "term", in: apps).first?.name == "Terminal", "prefix ranking")
expect(AppSearch.results(for: "terminal", in: apps).first?.name == "Terminal", "exact ranking")
expect(AppSearch.results(for: "am", in: apps).first?.name == "Activity Monitor", "initials")
expect(AppSearch.results(for: "gchr", in: apps).first?.name == "Google Chrome", "subsequence abbreviation")
expect(AppSearch.results(for: "cafe", in: apps).first?.name == "Café", "diacritic matching")
expect(AppSearch.results(for: "  TERM  ", in: apps).first?.name == "Terminal", "trim and fold case")
expect(AppSearch.results(for: "zzzzz", in: apps).isEmpty, "nonmatch")
expect(AppSearch.results(for: "", in: [app("Zebra"), app("Beta"), app("Alpha")], limit: 2).map(\.name) == ["Alpha", "Beta"], "empty query order and limit")
expect(AppSearch.results(for: "a", in: apps, limit: 0).isEmpty, "zero limit")
let temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
defer { try? FileManager.default.removeItem(at: temp) }
let root = temp.appendingPathComponent("Applications")
for path in ["Utilities/Terminal.app/Contents/Helpers/Hidden.app", "One.app/Contents", ".Private/Secret.app", "notes.txt"] {
    try FileManager.default.createDirectory(at: root.appendingPathComponent(path), withIntermediateDirectories: true)
}
let outside = temp.appendingPathComponent("Outside/Outside.app")
try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("Escape"), withDestinationURL: outside.deletingLastPathComponent())
try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("Linked.app"), withDestinationURL: outside)
var linkedApp = root.appendingPathComponent("Linked.app")
var hiddenFlag = URLResourceValues()
hiddenFlag.isHidden = true
try linkedApp.setResourceValues(hiddenFlag)
let indexed = ApplicationIndex.scan(roots: [root, root])
expect(Set(indexed.map(\.name)) == ["Terminal", "One", "Linked"], "roots, Utilities, bundle boundary, hidden/symlink exclusion")
expect(indexed.count == 3, "overlapping root deduplication")
expect(ApplicationIndex.scan(roots: [temp.appendingPathComponent("Missing")]).isEmpty, "missing roots")
print("PASS: \(checks) core checks")
let visible = CGRect(x: 0, y: 25, width: 1280, height: 775)
let fitted = PanelPlacement.fitted(CGRect(x: 320, y: -23, width: 640, height: 550), in: visible)
expect(visible.contains(fitted), "launcher stays inside 1280x800 visible screen")
let dragged = PanelPlacement.fitted(CGRect(x: -500, y: -300, width: 640, height: 550), in: visible)
expect(visible.contains(dragged), "resizing after drag is clamped")
expect(PanelPlacement.resultLimit(in: CGRect(x: 0, y: 0, width: 800, height: 400)) == 5, "small display caps visible result count")
print("PASS: placement checks; total \(checks)")

let projectsDirectory = URL(fileURLWithPath: "/Users/test/Applications")
let projectApps = ["Menagerie", "Quick Launch", "AppLab", "Gimme Job", "Atlas", "Matterlab"].map {
    Application(name: $0, url: projectsDirectory.appendingPathComponent("\($0).app"))
}
let shortcuts = ProjectShortcuts.applications(in: projectApps + [app("Other"), app("AppLab")], directory: projectsDirectory)
expect(shortcuts.map(\.name) == ["AppLab", "Gimme Job", "Matterlab", "Menagerie"], "only installed project apps in stable shortcut order")
expect(ProjectShortcuts.applications(in: [projectApps[0]], directory: projectsDirectory).map(\.name) == ["Menagerie"], "missing project apps omitted")
expect(ProjectShortcuts.applications(in: [app("AppLab")], directory: projectsDirectory).isEmpty, "unrelated same-name app excluded")
print("PASS: project shortcut checks; total \(checks)")

expect(ProjectToggleAction.decide(isRunning: false, isHidden: false, wasFrontmost: false) == .launch, "closed project launches")
expect(ProjectToggleAction.decide(isRunning: true, isHidden: false, wasFrontmost: true) == .hide, "frontmost project toggles hidden")
expect(ProjectToggleAction.decide(isRunning: true, isHidden: true, wasFrontmost: false) == .show, "hidden project toggles visible")
expect(ProjectToggleAction.decide(isRunning: true, isHidden: false, wasFrontmost: false) == .show, "background project comes forward before it can hide")
expect(!LauncherDismissal.shouldDismiss(click: CGPoint(x: 50, y: 50), panel: CGRect(x: 0, y: 0, width: 100, height: 100), isVisible: true), "inside click preserves launcher")
expect(LauncherDismissal.shouldDismiss(click: CGPoint(x: 150, y: 50), panel: CGRect(x: 0, y: 0, width: 100, height: 100), isVisible: true), "outside click dismisses launcher")
expect(!LauncherDismissal.shouldDismiss(click: CGPoint(x: 150, y: 50), panel: .zero, isVisible: false), "hidden launcher ignores background clicks")
print("PASS: toggle and dismissal checks; total \(checks)")

let usageSuite = "QuickLaunchChecks.\(UUID().uuidString)"
let usageDefaults = UserDefaults(suiteName: usageSuite)!
defer { usageDefaults.removePersistentDomain(forName: usageSuite) }
let history = ApplicationOpenHistory(defaults: usageDefaults)
let alphabetical = [app("Zebra"), app("Beta"), app("Alpha")]
expect(history.counts.isEmpty, "fresh history has no opens")
expect(AppSearch.results(for: "", in: alphabetical, openCounts: history.counts).map(\.name) == ["Alpha", "Beta", "Zebra"], "fresh usage retains alphabetical order")
history.recordOpen(app("Zebra"))
expect(AppSearch.results(for: "", in: alphabetical, openCounts: history.counts).map(\.name) == ["Zebra", "Alpha", "Beta"], "successful opens rank before alphabetical order")
history.recordOpen(app("Beta"))
expect(AppSearch.results(for: "", in: alphabetical, openCounts: history.counts).map(\.name) == ["Beta", "Zebra", "Alpha"], "equal open counts use alphabetical order")
history.recordOpen(app("Zebra"))
let restoredHistory = ApplicationOpenHistory(defaults: usageDefaults)
expect(restoredHistory.counts[app("Zebra").url.path] == 2, "counts accumulate and survive history reload")
expect(AppSearch.results(for: "", in: alphabetical, limit: 1, openCounts: restoredHistory.counts).first?.name == "Zebra", "limit is applied after frequency ordering")
let otherBeta = Application(name: "Beta", url: URL(fileURLWithPath: "/Other/Beta.app"))
expect(restoredHistory.counts[otherBeta.url.path] == nil, "same-name apps at different paths have separate histories")
expect(AppSearch.results(for: "alpha", in: alphabetical, openCounts: restoredHistory.counts).first?.name == "Alpha", "search relevance is retained despite usage")
expect(AppSearch.results(for: "a", in: [app("Able"), app("Axle")], openCounts: [app("Axle").url.path: 1]).first?.name == "Axle", "usage breaks equal-relevance search ties")
usageDefaults.set([app("Zebra").url.path: Int.max], forKey: "applicationOpenCounts")
let saturatedHistory = ApplicationOpenHistory(defaults: usageDefaults)
saturatedHistory.recordOpen(app("Zebra"))
expect(saturatedHistory.counts[app("Zebra").url.path] == Int.max, "counter saturation never overflows")
print("PASS: persistent usage ordering; total \(checks)")

let configurationSuite = "QuickLaunchConfigurationChecks.\(UUID().uuidString)"
let configurationDefaults = UserDefaults(suiteName: configurationSuite)!
defer { configurationDefaults.removePersistentDomain(forName: configurationSuite) }
let configuration = LauncherConfiguration(defaults: configurationDefaults)
expect(configuration.hotKey == .standard && configuration.locations == IndexLocation.standard && configuration.locations.allSatisfy { !$0.includesFiles }, "defaults keep Command-Space and Applications-only scanning")
let customKey = LauncherHotKey(keyCode: 40, modifiers: 5, key: "K")
configuration.setHotKey(customKey)
expect(LauncherConfiguration(defaults: configurationDefaults).hotKey == customKey, "configured hotkey persists")
expect(!LauncherHotKey(keyCode: 40, modifiers: 8, key: "K").isValid && !LauncherHotKey(keyCode: 999, modifiers: 1, key: "K").isValid, "plain typing and invalid keycodes cannot become global shortcuts")
configuration.setLocations([IndexLocation(path: root.path, includesFiles: true), IndexLocation(path: root.path, includesFiles: true)])
expect(configuration.locations.count == 1 && LauncherConfiguration(defaults: configurationDefaults).locations == configuration.locations, "index folders deduplicate and persist")
try Data("example".utf8).write(to: root.appendingPathComponent("example.txt"))
let contents = ApplicationIndex.scan(locations: configuration.locations)
expect(contents.contains { $0.name == "example.txt" && $0.kind == .file } && contents.contains { $0.name == "Utilities" && $0.kind == .folder }, "opted-in directories include files and folders")
expect(!ApplicationIndex.scan().contains { $0.kind != .application }, "default scan remains app-only")
expect(!contents.contains { $0.url.path.contains("Contents/Helpers") || $0.url.path.contains(".Private") || $0.url.path.contains("Escape/") }, "extra folders retain app-package, hidden and symlink traversal boundaries")
configuration.setLocations([])
expect(LauncherConfiguration(defaults: configurationDefaults).locations.isEmpty, "intentionally empty index survives restart")

let service = SpotlightService(label: "com.apple.mdworker.shared", domain: "gui/502", loaded: true, disabled: false)
expect(SpotlightServices.includes(service.label) && !SpotlightServices.includes("com.apple.fseventsd") && !SpotlightServices.includes("com.apple.backupd"), "Spotlight catalog excludes general filesystem and backup services")
expect(!SpotlightServices.isValidTarget(SpotlightService(label: service.label + ";touch /tmp/no", domain: service.domain, loaded: false, disabled: nil)), "command targets reject injected service labels")
expect(!SpotlightServices.isValidTarget(SpotlightService(label: service.label, domain: "gui/502/other", loaded: false, disabled: nil)), "command targets reject invalid launch domains")
expect(SpotlightServices.overrides("\"com.apple.mdworker.shared\" => true\n\"com.apple.mds\" => false")[service.label] == true, "Boolean launch policies parse correctly")
let inventoryFixture = "services = {\n  111 0 com.apple.mdworker.shared\n  - 0 com.apple.mds\n}\nendpoints = {\n  222 0 com.apple.not-a-job\n}"
expect(SpotlightServices.loadedLabels(inventoryFixture) == Set([service.label, "com.apple.mds"]), "inventory parses only the loaded-service table")
var commands: [[String]] = []
var policyReads = 0
var jobReads = 0
let disabledChanges = SpotlightServices.apply(SpotlightRequest(services: [service], disabled: true)) { args in
    commands.append(args)
    if args[0] == "print-disabled" { policyReads += 1; return CommandResult(0, "\"\(service.label)\" => \(policyReads == 1 ? "false" : "true")") }
    if args[0] == "print" { jobReads += 1; return jobReads == 1 ? CommandResult(0) : CommandResult(113, "", "Could not find service \"\(service.label)\"") }
    return CommandResult(0)
}
expect(disabledChanges.first?.succeeded == true && commands[2] == ["disable", service.target] && commands[3] == ["bootout", service.target], "disable policy precedes exact-domain stop and both are verified")
let stillLoaded = SpotlightServices.apply(SpotlightRequest(services: [service], disabled: true)) { args in
    args[0] == "print-disabled" ? CommandResult(0, "\"\(service.label)\" => true") : CommandResult(0)
}
expect(stillLoaded.first?.succeeded == false, "saved override alone cannot report successful disable")
let denied = SpotlightServices.apply(SpotlightRequest(services: [service], disabled: true)) { _ in CommandResult(1, "", "Operation not permitted") }
expect(denied.first?.succeeded == false && denied.first?.detail.contains("Operation not permitted") == true, "protected-service refusal is reported")
commands = []
let enabledChanges = SpotlightServices.apply(SpotlightRequest(services: [service], disabled: false)) { args in
    commands.append(args)
    return args[0] == "print-disabled" ? CommandResult(0, "\"\(service.label)\" => false") : CommandResult(0)
}
expect(enabledChanges.first?.succeeded == true && !commands.contains { $0[0] == "bootout" || $0[0] == "bootstrap" }, "enable verifies policy without stopping or starting jobs")
print("PASS: configurable settings and Spotlight command fixtures; total \(checks)")

expect(AppSearch.results(for: "", in: apps, shouldCancel: { true }).isEmpty, "superseded searches cancel before publishing results")
expect(ApplicationIndex.scan(roots: [root], includeFiles: true, shouldCancel: { true }).isEmpty, "superseded directory scans stop without walking contents")

print("PASS: all core checks; total \(checks)")

commands = []
let noJournal = SpotlightServices.apply(SpotlightRequest(services: [service], disabled: true), run: { args in
    commands.append(args)
    return args[0] == "print-disabled" ? CommandResult(0, "\"\(service.label)\" => false") : CommandResult(0)
}, beforeChange: { _ in false })
expect(noJournal.first?.succeeded == false && !commands.contains { ["disable", "enable", "bootout"].contains($0[0]) }, "unwritable authoritative before-journal prevents every mutation")
var beforeJournal: SpotlightService?
var recordedOutcomes = 0
let journalled = SpotlightServices.apply(SpotlightRequest(services: [service], disabled: false), run: { args in
    args[0] == "print-disabled" ? CommandResult(0, "\"\(service.label)\" => false") : CommandResult(0)
}, beforeChange: { beforeJournal = $0; return true }, saveResult: { _ in recordedOutcomes += 1; return true })
expect(beforeJournal?.loaded == true && beforeJournal?.disabled == false && recordedOutcomes == 1 && journalled.first?.succeeded == true, "fresh authoritative state and each outcome reach journal hooks")
let secondService = SpotlightService(label: "com.apple.corespotlightd", domain: service.domain, loaded: true, disabled: false)
commands = []
_ = SpotlightServices.apply(SpotlightRequest(services: [service, secondService], disabled: false), run: { args in
    commands.append(args)
    return args[0] == "print-disabled" ? CommandResult(0, "\"\(service.label)\" => false") : CommandResult(0)
}, saveResult: { _ in false })
expect(commands.filter { $0[0] == "enable" }.count == 1, "outcome-journal failure stops subsequent service mutations")
print("PASS: journal failure boundaries; total \(checks)")
