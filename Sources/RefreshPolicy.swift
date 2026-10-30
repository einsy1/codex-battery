import Foundation

enum QuotaFreshness { case current, cached, unavailable }

enum RefreshPolicy {
    static let normalInterval: TimeInterval = 180
    static func retryInterval(failures: Int, retryable: Bool) -> TimeInterval {
        guard retryable else { return normalInterval }
        switch failures { case ...1: return 10; case 2: return 30; case 3: return 60; default: return normalInterval }
    }
    static func freshness(updatedAt: Date?, resetAt: Date?, hasError: Bool, allowCached: Bool, now: Date = Date()) -> QuotaFreshness {
        guard let updatedAt, now.timeIntervalSince(updatedAt) <= 600 else { return .unavailable }
        if let resetAt, resetAt <= now { return .unavailable }
        if hasError { return allowCached ? .cached : .unavailable }
        return .current
    }
}
