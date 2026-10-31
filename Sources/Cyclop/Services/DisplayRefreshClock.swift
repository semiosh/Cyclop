import AppKit
import QuartzCore

/// A window-bound frame clock. AppKit follows the window's display and suspends
/// callbacks when it has no display. Callers start it only for active motion.
@MainActor
final class DisplayRefreshClock {
    private var link: CADisplayLink?
    private weak var window: NSWindow?
    private var onFrame: ((TimeInterval) -> Void)?
    private var observers: [NSObjectProtocol] = []
    private var accessibilityObserver: NSObjectProtocol?

    /// CADisplayLink retains its target. This proxy keeps that target from
    /// retaining the clock, and invalidates an orphaned link on its next frame.
    @MainActor
    private final class Target: NSObject {
        weak var clock: DisplayRefreshClock?
        init(clock: DisplayRefreshClock) { self.clock = clock }
        @objc func step(_ link: CADisplayLink) {
            guard let clock else { link.invalidate(); return }
            clock.onFrame?(link.targetTimestamp)
        }
    }

    func start(window: NSWindow, onFrame: @escaping (TimeInterval) -> Void) {
        stop()
        self.window = window
        self.onFrame = onFrame
        let target = Target(clock: self)
        let link = window.displayLink(target: target, selector: #selector(Target.step(_:)))
        self.link = link
        updateFrameRate()
        let center = NotificationCenter.default
        for name in [Notification.Name.NSProcessInfoPowerStateDidChange,
                     ProcessInfo.thermalStateDidChangeNotification,
                     NSWindow.didChangeScreenNotification] {
            observers.append(center.addObserver(
                forName: name,
                object: name == NSWindow.didChangeScreenNotification ? window : nil,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.updateFrameRate() }
            })
        }
        accessibilityObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateFrameRate() }
        }
        link.add(to: .main, forMode: .common)
    }

    func stop() {
        link?.invalidate()
        link = nil
        onFrame = nil
        window = nil
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
        observers.removeAll()
        if let accessibilityObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(accessibilityObserver)
        }
        accessibilityObserver = nil
    }

    private func updateFrameRate() {
        let process = ProcessInfo.processInfo
        let constrained = process.isLowPowerModeEnabled
            || process.thermalState == .serious || process.thermalState == .critical
            || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        link?.preferredFrameRateRange = FrameRefreshPolicy.range(
            maximumFPS: window?.screen?.maximumFramesPerSecond ?? 60,
            constrained: constrained
        )
    }
}

/// Hints, not a forced refresh rate: macOS still chooses the actual cadence.
enum FrameRefreshPolicy {
    static func range(maximumFPS: Int, constrained: Bool) -> CAFrameRateRange {
        let supported = maximumFPS > 0 ? maximumFPS : 60
        let maximum = Float(constrained ? min(supported, 60) : supported)
        return CAFrameRateRange(minimum: min(30, maximum), maximum: maximum, preferred: maximum)
    }
}
