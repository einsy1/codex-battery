import Foundation
import Darwin

struct QuotaWindow: Codable, Equatable {
    let usedPercent: Double
    let windowDurationMins: Int?
    let resetsAt: Double?
    var remaining: Double { min(100, max(0, 100 - usedPercent)) }
    var resetDate: Date? { resetsAt.map { Date(timeIntervalSince1970: $0) } }
}
struct QuotaBucket: Codable {
    let limitId: String?
    let primary: QuotaWindow?
    let secondary: QuotaWindow?
    let planType: String?
    let spendControlReached: Bool?
    let rateLimitReachedType: String?
}
struct QuotaResponse: Codable {
    let rateLimits: QuotaBucket?
    let rateLimitsByLimitId: [String: QuotaBucket]?
    let ordinaryUsageAllowed: Bool?
    var bucket: QuotaBucket? {
        if let codex = rateLimitsByLimitId?["codex"] { return codex }
        if rateLimits?.limitId == "codex" || rateLimits?.limitId == nil { return rateLimits }
        return nil
    }
    var fiveHour: QuotaWindow? { [bucket?.primary, bucket?.secondary].compactMap { $0 }.first { $0.windowDurationMins == 300 } }
    var weekly: QuotaWindow? { [bucket?.primary, bucket?.secondary].compactMap { $0 }.first { $0.windowDurationMins == 10080 } }
}
enum QuotaError: LocalizedError {
    case missingCLI, timeout, disconnected, server(String), missingWindow, invalidResponse
    var retryable: Bool {
        switch self {
        case .missingCLI, .missingWindow, .invalidResponse: return false
        case .server(let message): return !Self.isAuthentication(message)
        case .timeout, .disconnected: return true
        }
    }
    private static func isAuthentication(_ message: String) -> Bool {
        let value = message.lowercased()
        return ["unauthorized", "authentication", "login", "log in", "sign in", "401", "token expired", "refresh token"].contains { value.contains($0) }
    }
    var errorDescription: String? {
        switch self {
        case .missingCLI: return "未找到 Codex。请安装 Codex，或在设置中选择 codex 可执行文件。"
        case .timeout: return "连接超时，请检查网络后重试。"
        case .disconnected: return "Codex 连接已中断，请稍后重试。"
        case .server(let message):
            if Self.isAuthentication(message) { return "Codex 登录状态需要更新，请在 Codex 中重新登录后刷新。" }
            let value = message.lowercased()
            if value.contains("429") || value.contains("too many requests") || value.contains("rate limit") { return "额度查询暂时被限流，将自动重试。" }
            if ["network", "connect", "dns", "fetch", "timed out", "timeout"].contains(where: { value.contains($0) }) { return "额度服务连接失败，将自动重试。" }
            return "额度服务暂时未返回结果，将自动重试。"
        case .invalidResponse: return "额度数据格式不兼容，请更新应用后重试。"
        case .missingWindow: return "当前账户没有返回五小时额度。请确认使用 ChatGPT 账户登录。"
        }
    }
}

// Only the supported local protocol is used. No credentials are opened or copied.
struct QuotaClient {
    static func executable(custom: String? = nil) -> URL? {
        let candidates = [custom,
            "/Applications/Codex.app/Contents/Resources/codex",
            "/Applications/Codex.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex",
            "/Applications/ChatGPT.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex",
            "/opt/homebrew/bin/codex", "/usr/local/bin/codex",
            NSHomeDirectory() + "/.local/bin/codex"]
        for path in candidates.compactMap({ $0 }) where !path.isEmpty {
            if FileManager.default.isExecutableFile(atPath: path) { return URL(fileURLWithPath: path) }
        }
        return nil
    }
    static func fetch(custom: String? = nil, timeout: TimeInterval = 25) throws -> QuotaResponse {
        guard let executable = executable(custom: custom) else { throw QuotaError.missingCLI }
        let process = Process()
        let input = Pipe(), output = Pipe()
        process.executableURL = executable
        process.arguments = ["app-server", "--stdio"]
        process.standardInput = input; process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        process.currentDirectoryURL = FileManager.default.temporaryDirectory
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        process.environment = environment
        try process.run()
        let deadline = Date().addingTimeInterval(max(0.01, timeout))
        defer {
            try? input.fileHandleForWriting.close()
            if process.isRunning { process.terminate() }
            let grace = Date().addingTimeInterval(0.3)
            while process.isRunning && Date() < grace { usleep(10_000) }
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
            process.waitUntilExit()
            try? output.fileHandleForReading.close()
        }
        func send(_ object: [String: Any]) throws {
            var data = try JSONSerialization.data(withJSONObject: object)
            data.append(10)
            try input.fileHandleForWriting.write(contentsOf: data)
        }
        try send(["id": 1, "method": "initialize", "params": ["clientInfo": ["name": "codex_battery", "title": "Codex Battery", "version": "1.1.2"]]])
        var buffer = Data()
        while Date() < deadline {
            // Poll instead of blocking in availableData: a hung child cannot hold loading=true forever.
            var descriptor = pollfd(fd: output.fileHandleForReading.fileDescriptor, events: Int16(POLLIN | POLLHUP), revents: 0)
            let remainingMs = max(1, min(1_000, Int(deadline.timeIntervalSinceNow * 1_000)))
            let ready = poll(&descriptor, 1, Int32(remainingMs))
            if ready < 0 { if errno == EINTR { continue }; throw QuotaError.disconnected }
            if ready == 0 { continue }
            var bytes = [UInt8](repeating: 0, count: 65_536)
            let count = bytes.withUnsafeMutableBytes { Darwin.read(descriptor.fd, $0.baseAddress, $0.count) }
            if count < 0 { if errno == EINTR { continue }; throw QuotaError.disconnected }
            if count == 0 { throw Date() >= deadline ? QuotaError.timeout : QuotaError.disconnected }
            buffer.append(contentsOf: bytes.prefix(count))
            if buffer.count > 4_000_000 { throw QuotaError.disconnected }
            while let end = buffer.firstIndex(of: 10) {
                let line = buffer.prefix(upTo: end)
                buffer.removeSubrange(...end)
                guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else { continue }
                if let error = object["error"] as? [String: Any], object["id"] != nil {
                    throw QuotaError.server(error["message"] as? String ?? "")
                }
                if object["id"] as? Int == 1 {
                    try send(["method": "initialized", "params": [:] as [String: String]])
                    try send(["id": 2, "method": "account/rateLimits/read", "params": [:] as [String: String]])
                } else if object["id"] as? Int == 2, let result = object["result"] {
                    let response: QuotaResponse
                    do { response = try JSONDecoder().decode(QuotaResponse.self, from: JSONSerialization.data(withJSONObject: result)) }
                    catch { throw QuotaError.invalidResponse }
                    guard response.fiveHour != nil else { throw QuotaError.missingWindow }
                    return response
                }
            }
        }
        throw QuotaError.timeout
    }
}
