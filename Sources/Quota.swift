import Foundation

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
    case missingCLI, timeout, disconnected, server(String), missingWindow
    var errorDescription: String? {
        switch self {
        case .missingCLI: return "未找到 Codex。请安装 Codex，或在设置中选择 codex 可执行文件。"
        case .timeout: return "连接超时，请检查网络后重试。"
        case .disconnected: return "Codex 连接已中断，请稍后重试。"
        case .server(let message):
            if message.lowercased().contains("auth") || message.lowercased().contains("login") { return "请先在 Codex 中使用 ChatGPT 账户登录，再回来刷新。" }
            return "暂时无法读取额度，请稍后重试。"
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
    static func fetch(custom: String? = nil) throws -> QuotaResponse {
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
        let deadline = Date().addingTimeInterval(25)
        let timeout = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + 25, execute: timeout)
        defer {
            timeout.cancel()
            try? input.fileHandleForWriting.close()
            if process.isRunning { process.terminate() }
            process.waitUntilExit()
            try? output.fileHandleForReading.close()
        }
        func send(_ object: [String: Any]) throws {
            var data = try JSONSerialization.data(withJSONObject: object)
            data.append(10)
            try input.fileHandleForWriting.write(contentsOf: data)
        }
        try send(["id": 1, "method": "initialize", "params": ["clientInfo": ["name": "codex_battery", "title": "Codex Battery", "version": "1.1.0"]]])
        var buffer = Data()
        while Date() < deadline {
            let chunk = output.fileHandleForReading.availableData
            if chunk.isEmpty { throw Date() >= deadline ? QuotaError.timeout : QuotaError.disconnected }
            buffer.append(chunk)
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
                    let response = try JSONDecoder().decode(QuotaResponse.self, from: JSONSerialization.data(withJSONObject: result))
                    guard response.fiveHour != nil else { throw QuotaError.missingWindow }
                    return response
                }
            }
        }
        throw QuotaError.timeout
    }
}
