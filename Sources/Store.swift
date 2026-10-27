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
    private var timer: Timer?
    private var failures = 0
    private var lastAttempt: Date?
    var fiveHour: QuotaWindow? { response?.fiveHour }
    var weekly: QuotaWindow? { response?.weekly }
    var stale: Bool { error != nil || updatedAt.map { Date().timeIntervalSince($0) > 600 } ?? true }
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
        loading = true; lastAttempt = Date(); onChange?()
        let path = UserDefaults.standard.string(forKey: "codexPath")
        Task { [self] in
            let result = await Task.detached(priority: .utility) { () -> Result<QuotaResponse, Error> in
                Result { try QuotaClient.fetch(custom: path) }
            }.value
            loading = false
            switch result {
            case .success(let value):
                response = value; updatedAt = Date(); error = nil; failures = 0
            case .failure(let failure):
                error = failure.localizedDescription; failures += 1
            }
            onChange?()
            var interval = min(900.0, 180.0 * pow(2, Double(min(failures, 3))))
            if let reset = fiveHour?.resetDate, reset > Date() {
                interval = min(interval, max(2, reset.timeIntervalSinceNow + 2))
            }
            timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
                Task { @MainActor in self?.refresh() }
            }
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
