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
