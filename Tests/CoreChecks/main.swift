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
