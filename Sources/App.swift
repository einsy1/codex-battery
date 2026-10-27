import AppKit
import SwiftUI

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    let store = QuotaStore()
    private var status: NSStatusItem!
    private let popover = NSPopover()
    private var wakeObserver: NSObjectProtocol?
    private var freshnessTimer: Timer?
    private var iconAnimation: Timer?
    private var displayedRemaining: Double?
    private var renderedStyle: StatusIconStyle?
    private var wasLoading = false
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        status = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = status.button {
            button.target = self; button.action = #selector(togglePopover)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.imagePosition = .imageLeading
        }
        popover.behavior = .transient
        popover.animates = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        popover.delegate = self
        store.onChange = { [weak self] in self?.updateStatus() }
        updateStatus()
        store.start()
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.store.refresh() }
        }
        freshnessTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.updateStatus() }
        }
        let firstLaunch = !UserDefaults.standard.bool(forKey: "hasLaunched")
        UserDefaults.standard.set(true, forKey: "hasLaunched")
        if firstLaunch || ProcessInfo.processInfo.arguments.contains("--show") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { self.showPopover() }
        }
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showPopover(); return true
    }
    func updateStatus() {
        guard let button = status.button else { return }
        let remaining = store.fiveHour?.remaining
        let target = store.stale ? nil : remaining
        let shouldAnimate = target != displayedRemaining || renderedStyle != store.iconStyle || store.loading != wasLoading
        if shouldAnimate {
            animateIcon(to: target)
        } else if iconAnimation == nil {
            button.image = StatusIconRenderer.image(style: store.iconStyle, remaining: target)
        }
        wasLoading = store.loading
        renderedStyle = store.iconStyle
        button.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        button.title = store.showPercentage ? (store.stale ? " —" : " \(Int((remaining ?? 0).rounded()))%") : ""
        button.toolTip = store.stale ? "Codex Battery · 等待更新" : "Codex 五小时可用量 \(Int((remaining ?? 0).rounded()))%"
        button.setAccessibilityLabel("\(store.iconStyle.title) · \(button.toolTip ?? "Codex Battery")")
    }
    private func animateIcon(to target: Double?) {
        iconAnimation?.invalidate(); iconAnimation = nil
        let start = displayedRemaining ?? target
        let style = store.iconStyle
        let refreshing = store.loading
        displayedRemaining = target
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            status.button?.image = StatusIconRenderer.image(style: style, remaining: target)
            return
        }
        let began = Date()
        let duration = 0.65
        status.button?.image = StatusIconRenderer.image(style: style, remaining: start)
        let timer = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] timer in
            Task { @MainActor in
                guard let self else { timer.invalidate(); return }
                let t = min(1, Date().timeIntervalSince(began) / duration)
                let eased = 1 - pow(1 - t, 3)
                let value: Double? = target.flatMap { end in start.map { $0 + (end - $0) * eased } ?? end }
                self.status.button?.image = StatusIconRenderer.image(style: style, remaining: value, phase: t, refreshing: refreshing)
                if t >= 1 { timer.invalidate(); self.iconAnimation = nil }
            }
        }
        iconAnimation = timer
        RunLoop.main.add(timer, forMode: .common)
    }
    @objc func togglePopover() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            let menu = NSMenu()
            let refresh = NSMenuItem(title: "立即刷新", action: #selector(refresh), keyEquivalent: "r"); refresh.target = self
            menu.addItem(refresh); menu.addItem(.separator())
            let quit = NSMenuItem(title: "退出 Codex Battery", action: #selector(quit), keyEquivalent: "q"); quit.target = self
            menu.addItem(quit)
            status.menu = menu; status.button?.performClick(nil); status.menu = nil
        } else if popover.isShown { popover.performClose(nil) }
        else { showPopover() }
    }
    @objc func refresh() { store.refresh() }
    @objc func quit() { NSApp.terminate(nil) }
    func showPopover() {
        guard let button = status.button else { return }
        let controller = NSHostingController(rootView: QuotaPanel(store: store))
        controller.sizingOptions = [.preferredContentSize]
        popover.contentViewController = controller
        store.refreshIfNeeded()
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }
    func applicationWillTerminate(_ notification: Notification) {
        if let wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver) }
        freshnessTimer?.invalidate()
        iconAnimation?.invalidate()
    }
}

@main struct Entry {
    static func main() {
        if CommandLine.arguments.contains("--probe") {
            do {
                let response = try QuotaClient.fetch()
                let summary: [String: Any] = ["fiveHourRemaining": response.fiveHour?.remaining ?? -1,
                    "weeklyRemaining": response.weekly?.remaining ?? -1,
                    "resetTimestamp": response.fiveHour?.resetsAt ?? 0,
                    "windowMinutes": response.fiveHour?.windowDurationMins ?? 0]
                let data = try JSONSerialization.data(withJSONObject: summary, options: [.prettyPrinted, .sortedKeys])
                print(String(decoding: data, as: UTF8.self))
                exit(0)
            } catch { fputs("\(error.localizedDescription)\n", stderr); exit(1) }
        }
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
        withExtendedLifetime(delegate) {}
    }
}
