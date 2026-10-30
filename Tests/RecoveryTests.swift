import Foundation
@main struct RecoveryTests {
    static func main() throws {
        func check(_ condition: Bool, _ label: String) { precondition(condition, label); print("PASS \(label)") }
        let now = Date()
        check(RefreshPolicy.retryInterval(failures:1,retryable:true) == 10, "first transient failure retries after 10 seconds")
        check(RefreshPolicy.retryInterval(failures:2,retryable:true) == 30 && RefreshPolicy.retryInterval(failures:3,retryable:true) == 60 && RefreshPolicy.retryInterval(failures:20,retryable:true) == 180, "repeated failures are bounded to three minutes")
        check(RefreshPolicy.retryInterval(failures:1,retryable:false) == 180, "authentication or incompatible response does not trigger rapid retries")
        let recent = now.addingTimeInterval(-30), future = now.addingTimeInterval(500)
        check(RefreshPolicy.freshness(updatedAt:recent,resetAt:future,hasError:true,allowCached:true,now:now) == .cached, "brief failure retains recent data as explicitly cached")
        check(RefreshPolicy.freshness(updatedAt:recent,resetAt:future,hasError:true,allowCached:false,now:now) == .unavailable, "authentication failure never reuses cached quota")
        check(RefreshPolicy.freshness(updatedAt:now.addingTimeInterval(-601),resetAt:future,hasError:true,allowCached:true,now:now) == .unavailable, "ten-minute-old data is hidden")
        check(RefreshPolicy.freshness(updatedAt:recent,resetAt:now.addingTimeInterval(-1),hasError:false,allowCached:true,now:now) == .unavailable, "old window data cannot cross a reset")
        check(RefreshPolicy.freshness(updatedAt:recent,resetAt:future,hasError:false,allowCached:true,now:now) == .current, "successful refresh restores current state")
        check(RefreshPolicy.freshness(updatedAt:nil,resetAt:nil,hasError:true,allowCached:true,now:now) == .unavailable, "startup failure never invents cached data")
        check(!QuotaError.server("authentication required").retryable && QuotaError.server("429 Too many requests").retryable, "authentication and transient rate limiting classified separately")
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("quota-transport-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        defer { try? FileManager.default.removeItem(at:directory) }
        func fixture(_ name:String, _ body:String) throws -> String {
            let file = directory.appendingPathComponent(name)
            try ("#!/usr/bin/python3\n" + body).write(to:file,atomically:true,encoding:.utf8)
            try FileManager.default.setAttributes([.posixPermissions:0o755],ofItemAtPath:file.path)
            return file.path
        }
        let success = try fixture("fragmented", """
import sys,json,time
for line in sys.stdin:
 d=json.loads(line)
 if d.get('id')==1: print(json.dumps({'id':1,'result':{}}),flush=True)
 if d.get('id')==2:
  text=json.dumps({'id':2,'result':{'rateLimits':{'primary':{'usedPercent':23,'windowDurationMins':300}}}})+'\\n'
  sys.stdout.write(text[:21]);sys.stdout.flush();time.sleep(.02);sys.stdout.write(text[21:]);sys.stdout.flush()
""")
        check(try QuotaClient.fetch(custom:success,timeout:3).fiveHour?.remaining == 77,"fragmented protocol response parsed after handshake")
        let failure = try fixture("limited", """
import sys,json
for line in sys.stdin:
 d=json.loads(line)
 if d.get('id')==1: print(json.dumps({'id':1,'result':{}}),flush=True)
 if d.get('id')==2: print(json.dumps({'id':2,'error':{'code':-32000,'message':'429 Too many requests'}}),flush=True)
""")
        do { _ = try QuotaClient.fetch(custom:failure,timeout:3); preconditionFailure("expected error") }
        catch let error as QuotaError { check(error.retryable && error.localizedDescription.contains("限流"),"actual server error produces safe, actionable reason") }
        check(try QuotaClient.fetch(custom:success,timeout:3).fiveHour?.remaining == 77,"new request recovers after an upstream failure")
        let hanging = try fixture("hang", "import signal,time\nsignal.signal(signal.SIGTERM,signal.SIG_IGN)\ntime.sleep(20)\n")
        let began=Date()
        do { _ = try QuotaClient.fetch(custom:hanging,timeout:0.4); preconditionFailure("expected timeout") }
        catch let error as QuotaError {
            if case .timeout = error {} else { preconditionFailure("wrong timeout classification") }
            check(Date().timeIntervalSince(began) < 2,"silent child that ignores SIGTERM is killed without hanging refresh")
        }
    }
}
