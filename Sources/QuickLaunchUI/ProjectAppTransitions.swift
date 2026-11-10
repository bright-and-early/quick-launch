import AppKit
import QuartzCore
import ScreenCaptureKit
import QuickLaunchCore

/// App-wide hide/show with an ephemeral, window-only snapshot. Nothing is recorded to disk.
final class ProjectAppTransitions {
    private struct Snapshot {
        let image: CGImage
        let frame: CGRect
        let pid: pid_t
    }
    private var snapshots: [URL: Snapshot] = [:]
    private var task: Task<Void, Never>?
    private var finishAnimation: (() -> Void)?
    private var restoreOnCancel: (() -> Void)?
    private var requestedPermission = false
    var isBusy: Bool { task != nil }

    func requestPermission() {
        guard !CGPreflightScreenCaptureAccess() else { return }
        requestedPermission = true
        _ = CGRequestScreenCaptureAccess()
    }

    func cancel() {
        task?.cancel()
        finishAnimation?()
        restoreOnCancel?()
        restoreOnCancel = nil
    }

    func toggle(_ application: Application, anchor: CGRect, previousFrontmost: NSRunningApplication?, completion: @escaping () -> Void) {
        guard task == nil else { return }
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        // This path only runs after a deliberate project-logo click, never at startup.
        if !reduceMotion && !requestedPermission && !CGPreflightScreenCaptureAccess() { requestPermission() }
        let canCapture = CGPreflightScreenCaptureAccess()
        task = ProjectTransitionTask.start(completion: { [weak self] in
            self?.task = nil
            self?.restoreOnCancel = nil
            completion()
        }) { [weak self] in
            guard let self = self else { return }
            do {
                let running = NSWorkspace.shared.runningApplications.first {
                    $0.bundleURL?.resolvingSymlinksInPath() == application.url.resolvingSymlinksInPath() && !$0.isTerminated
                }
                let wasFrontmost = running.map { $0.isActive || $0.processIdentifier == previousFrontmost?.processIdentifier } ?? false
                let action = ProjectToggleAction.decide(isRunning: running != nil, isHidden: running?.isHidden ?? false, wasFrontmost: wasFrontmost)
                let target: NSRunningApplication
                if let running = running { target = running }
                else {
                    let config = NSWorkspace.OpenConfiguration()
                    config.activates = false
                    config.hides = canCapture
                    target = try await NSWorkspace.shared.openApplication(at: application.url, configuration: config)
                }
                try Task.checkCancellation()
                self.snapshots = self.snapshots.filter { NSRunningApplication(processIdentifier: $0.value.pid)?.isTerminated == false }
                var snapshot = self.snapshots[application.url].flatMap { $0.pid == target.processIdentifier ? $0 : nil }
                if canCapture, #available(macOS 14.0, *) {
                    if action == .hide || snapshot == nil {
                        // A new application may need a moment to create its first window.
                        for attempt in 0..<4 {
                            snapshot = try? await self.capture(target)
                            try Task.checkCancellation()
                            if snapshot != nil { break }
                            if attempt < 3 { try await Task.sleep(nanoseconds: 50_000_000) }
                        }
                    }
                }
                try Task.checkCancellation()
                if let snapshot = snapshot { self.snapshots[application.url] = snapshot }
                if action == .hide {
                    if let snapshot = snapshot, canCapture {
                        await self.animate(snapshot, anchor: anchor, showing: false, reduceMotion: reduceMotion) { _ = target.hide() }
                    } else { _ = target.hide() }
                } else {
                    let originallyHidden = target.isHidden
                    self.restoreOnCancel = {
                        if !originallyHidden { _ = target.unhide() }
                    }
                    if let snapshot = snapshot, canCapture {
                        await self.animate(snapshot, anchor: anchor, showing: true, reduceMotion: reduceMotion) { _ = target.hide() }
                    }
                    try Task.checkCancellation()
                    _ = target.unhide()
                    _ = target.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
                }
            } catch is CancellationError {
                // Cancellation never steals focus back. If a launch already began,
                // its hidden application stays hidden until the next deliberate click.
            } catch {
                guard !Task.isCancelled else { return }
                let alert = NSAlert()
                alert.messageText = "Could not toggle \(application.name)"
                alert.informativeText = error.localizedDescription
                alert.runModal()
            }
        }
    }

    @available(macOS 14.0, *)
    @MainActor private func capture(_ application: NSRunningApplication) async throws -> Snapshot? {
        let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: false)
        let windows = content.windows.filter {
            $0.owningApplication?.processID == application.processIdentifier && $0.windowLayer == 0 && $0.frame.width > 80 && $0.frame.height > 80
        }.sorted {
            if $0.isOnScreen != $1.isOnScreen { return $0.isOnScreen }
            return $0.frame.width * $0.frame.height > $1.frame.width * $1.frame.height
        }
        guard let window = windows.first else { return nil }
        let config = SCStreamConfiguration()
        let scale = min(2, 1600 / max(window.frame.width, window.frame.height))
        config.width = max(1, Int(window.frame.width * scale))
        config.height = max(1, Int(window.frame.height * scale))
        config.showsCursor = false
        config.ignoreShadowsSingleWindow = true
        let image = try await SCScreenshotManager.captureImage(contentFilter: SCContentFilter(desktopIndependentWindow: window), configuration: config)
        let desktopTop = NSScreen.screens.first?.frame.maxY ?? window.frame.maxY
        let frame = CGRect(x: window.frame.minX, y: desktopTop - window.frame.maxY, width: window.frame.width, height: window.frame.height)
        return Snapshot(image: image, frame: frame, pid: application.processIdentifier)
    }

    @MainActor private func animate(_ snapshot: Snapshot, anchor: CGRect, showing: Bool, reduceMotion: Bool, prepare: () -> Void) async {
        guard let plan = WindowTransitionPlan(window: snapshot.frame, icon: anchor) else { prepare(); return }
        let overlay = NSPanel(contentRect: plan.overlay, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        overlay.isOpaque = false
        overlay.backgroundColor = .clear
        overlay.hasShadow = false
        overlay.ignoresMouseEvents = true
        overlay.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1)
        overlay.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        let canvas = NSView(frame: CGRect(origin: .zero, size: plan.overlay.size))
        canvas.wantsLayer = true
        overlay.contentView = canvas
        let layer = CALayer()
        layer.anchorPoint = .zero
        layer.bounds = CGRect(origin: .zero, size: plan.expanded.size)
        layer.contents = snapshot.image
        layer.contentsGravity = .resize
        layer.masksToBounds = true
        layer.cornerRadius = 10
        canvas.layer!.addSublayer(layer)
        let collapsed = CATransform3DMakeScale(plan.collapsed.width / plan.expanded.width, plan.collapsed.height / plan.expanded.height, 1)
        let fromTransform = reduceMotion || !showing ? CATransform3DIdentity : collapsed
        let toTransform = reduceMotion || showing ? CATransform3DIdentity : collapsed
        let fromPosition = reduceMotion || !showing ? plan.expanded.origin : plan.collapsed.origin
        let toPosition = reduceMotion || showing ? plan.expanded.origin : plan.collapsed.origin
        let fromOpacity: Float = showing ? 0.05 : 1
        let toOpacity: Float = showing ? 1 : 0.05
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.position = fromPosition
        layer.transform = fromTransform
        layer.opacity = fromOpacity
        CATransaction.commit()
        overlay.orderFrontRegardless()
        prepare()
        await withCheckedContinuation { continuation in
            var finished = false
            let finish = { [weak self] in
                guard !finished else { return }
                finished = true
                layer.removeAllAnimations()
                overlay.orderOut(nil)
                self?.finishAnimation = nil
                continuation.resume()
            }
            self.finishAnimation = finish
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            layer.position = toPosition
            layer.transform = toTransform
            layer.opacity = toOpacity
            CATransaction.commit()
            let transform = CABasicAnimation(keyPath: "transform")
            transform.fromValue = NSValue(caTransform3D: fromTransform)
            transform.toValue = NSValue(caTransform3D: toTransform)
            let position = CABasicAnimation(keyPath: "position")
            position.fromValue = NSValue(point: fromPosition)
            position.toValue = NSValue(point: toPosition)
            let opacity = CABasicAnimation(keyPath: "opacity")
            opacity.fromValue = fromOpacity
            opacity.toValue = toOpacity
            let group = CAAnimationGroup()
            group.animations = [transform, position, opacity]
            group.duration = reduceMotion ? 0.08 : 0.22
            group.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.8, 0.2, 1)
            CATransaction.begin()
            CATransaction.setCompletionBlock { DispatchQueue.main.async(execute: finish) }
            layer.add(group, forKey: "project-window-transition")
            CATransaction.commit()
        }
    }
}
