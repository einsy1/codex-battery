import AppKit
import Foundation

final class ScriptedBackend: @unchecked Sendable {
    private let lock = NSLock()
    private var calls = 0
    var count: Int { lock.lock(); defer { lock.unlock() }; return calls }
    func fetch() throws -> QuotaResponse {
        lock.lock(); calls += 1; let call = calls; lock.unlock()
        if call == 2 { throw QuotaError.server("503 temporary service unavailable") }
        let used = call == 1 ? 23 : 24
        let json = "{\"rateLimits\":{\"primary\":{\"usedPercent\":\(used),\"windowDurationMins\":300,\"resetsAt\":\(Date().addingTimeInterval(3600).timeIntervalSince1970)}}}"
        return try JSONDecoder().decode(QuotaResponse.self,from:Data(json.utf8))
    }
}
@main struct StoreRecoveryTests {
    @MainActor static func main() {
        let application = NSApplication.shared
        application.setActivationPolicy(.prohibited)
        Task { @MainActor in
            func check(_ condition:Bool,_ label:String) { precondition(condition,label); print("PASS \(label)") }
            @MainActor func waitUntil(_ predicate: @MainActor () -> Bool, timeout: TimeInterval = 3) async -> Bool {
                let deadline = Date().addingTimeInterval(timeout)
                while !predicate() && Date() < deadline { try? await Task.sleep(nanoseconds:20_000_000) }
                return predicate()
            }
            let backend = ScriptedBackend()
            let store = QuotaStore(fetcher:{ _ in try backend.fetch() })
            store.start()
            let initial = await waitUntil { !store.loading }
            check(initial && store.menuRemaining == 77 && !store.cachedForMenu,"store displays initial successful read")
            store.refresh()
            let failed = await waitUntil { !store.loading }
            check(failed && store.error != nil && store.menuRemaining == 77 && store.cachedForMenu,"store preserves and labels recent quota through a transient failure")
            let delay = store.nextRetryAt?.timeIntervalSinceNow ?? -1
            check(delay > 8 && delay <= 10,"store actually schedules first retry for ten seconds")
            let recovered = await waitUntil({ backend.count >= 3 && !store.loading },timeout:13)
            check(recovered && store.menuRemaining == 76 && store.error == nil && !store.cachedForMenu && store.nextRetryAt == nil,"real run-loop timer retries and restores current data without user action")
            exit(0)
        }
        application.run()
    }
}
