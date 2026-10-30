import AppKit
import SwiftUI
import ServiceManagement

@MainActor final class QuotaStore: ObservableObject {
    @Published var response: QuotaResponse?
    @Published var updatedAt: Date?
    @Published var loading = false
    @Published var error: String?
    @Published var settingsError: String?
    @Published var launchAtLogin = SMAppService.mainApp.status == .enabled
    @Published var showPercentage = UserDefaults.standard.object(forKey: "showPercentage") as? Bool ?? true
    @Published var iconStyle = StatusIconStyle.restored()
    var onChange: (() -> Void)?
    private let fetcher: @Sendable (String?) throws -> QuotaResponse
    init(fetcher: @escaping @Sendable (String?) throws -> QuotaResponse = { try QuotaClient.fetch(custom: $0) }) {
        self.fetcher = fetcher
    }
    private var timer: Timer?
    private var failures = 0
    private var lastAttempt: Date?
    private var allowCached = true
    @Published var nextRetryAt: Date?
    var freshness: QuotaFreshness {
        RefreshPolicy.freshness(updatedAt: updatedAt, resetAt: fiveHour?.resetDate, hasError: error != nil, allowCached: allowCached)
    }
    var menuRemaining: Double? { freshness == .unavailable ? nil : fiveHour?.remaining }
    var cachedForMenu: Bool { freshness == .cached }
    func updateFreshness() { objectWillChange.send(); onChange?() }
    var fiveHour: QuotaWindow? { response?.fiveHour }
    var weekly: QuotaWindow? { response?.weekly }
    var stale: Bool { freshness != .current }
    var unavailable: Bool { response?.ordinaryUsageAllowed == false || response?.bucket?.spendControlReached == true || weekly?.remaining == 0 || fiveHour?.remaining == 0 }
    var tint: Color {
        guard !stale else { return .secondary }
        let value = fiveHour?.remaining ?? 0
        return unavailable || value <= 10 ? .red : value <= 25 ? .orange : Color(red: 0.12, green: 0.67, blue: 0.48)
    }
    func start() { refresh() }
    func refreshIfNeeded() {
        if lastAttempt.map({ Date().timeIntervalSince($0) >= 30 }) ?? true { refresh() }
    }
    func refresh() {
        guard !loading else { return }
        timer?.invalidate()
        loading = true; nextRetryAt = nil; lastAttempt = Date(); onChange?()
        let path = UserDefaults.standard.string(forKey: "codexPath")
        let fetcher = self.fetcher
        Task { [self] in
            let result = await Task.detached(priority: .utility) { () -> Result<QuotaResponse, Error> in
                Result { try fetcher(path) }
            }.value
            loading = false
            var retryable = true
            switch result {
            case .success(let value):
                response = value; updatedAt = Date(); error = nil; failures = 0; allowCached = true
            case .failure(let failure):
                error = failure.localizedDescription; failures += 1
                retryable = (failure as? QuotaError)?.retryable ?? true
                allowCached = retryable
            }
            onChange?()
            var interval = error == nil ? RefreshPolicy.normalInterval : RefreshPolicy.retryInterval(failures: failures, retryable: retryable)
            if let reset = fiveHour?.resetDate, reset > Date() {
                interval = min(interval, max(2, reset.timeIntervalSinceNow + 2))
            }
            if error != nil { nextRetryAt = Date().addingTimeInterval(interval) }
            timer = Timer(timeInterval: interval, repeats: false) { [weak self] _ in
                Task { @MainActor in self?.refresh() }
            }
            if let timer { RunLoop.main.add(timer, forMode: .common) }
        }
    }
    func setIconStyle(_ style: StatusIconStyle) {
        guard iconStyle != style else { return }
        iconStyle = style
        UserDefaults.standard.set(style.rawValue, forKey: "statusIconStyle")
        onChange?()
    }
    func setPercentage(_ enabled: Bool) {
        showPercentage = enabled
        UserDefaults.standard.set(enabled, forKey: "showPercentage")
        onChange?()
    }
    func toggleLogin() {
        do {
            if launchAtLogin { try SMAppService.mainApp.unregister() }
            else { try SMAppService.mainApp.register() }
            launchAtLogin = SMAppService.mainApp.status == .enabled
            if SMAppService.mainApp.status == .requiresApproval { settingsError = "请在系统设置 → 通用 → 登录项中允许 Codex Battery。" }
        } catch { settingsError = "未能更改登录项：\(error.localizedDescription)" }
    }
    func selectExecutable() {
        let panel = NSOpenPanel()
        panel.title = "选择 codex 可执行文件"
        panel.canChooseDirectories = false; panel.allowsMultipleSelection = false
        panel.showsHiddenFiles = true
        if panel.runModal() == .OK, let url = panel.url {
            guard FileManager.default.isExecutableFile(atPath: url.path) else { settingsError = "所选文件无法执行，请选择 codex 程序。"; return }
            UserDefaults.standard.set(url.path, forKey: "codexPath"); refresh()
        }
    }
}
