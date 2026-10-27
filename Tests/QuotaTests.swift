import Foundation
@main struct QuotaTests {
 static func main() throws {
  func parse(_ raw: String) throws -> QuotaResponse { try JSONDecoder().decode(QuotaResponse.self,from:Data(raw.utf8)) }
  func check(_ condition: Bool, _ label: String) { if !condition { fatalError(label) }; print("PASS \(label)") }
  let multi = try parse(#"{"rateLimits":{"limitId":"codex","primary":{"usedPercent":80,"windowDurationMins":300}},"rateLimitsByLimitId":{"codex":{"limitId":"codex","primary":{"usedPercent":22,"windowDurationMins":10080},"secondary":{"usedPercent":13,"windowDurationMins":300,"resetsAt":1793108274}}}}"#)
  check(multi.fiveHour?.remaining == 87, "multi-bucket preferred; five-hour window selected by duration")
  check(multi.weekly?.remaining == 78, "weekly selected independently of primary/secondary position")
  check(multi.fiveHour?.resetDate == Date(timeIntervalSince1970:1793108274), "server reset timestamp preserved")
  let legacy = try parse(#"{"rateLimits":{"primary":{"usedPercent":37.5,"windowDurationMins":300},"secondary":null}}"#)
  check(legacy.fiveHour?.remaining == 62.5 && legacy.weekly == nil, "legacy and absent weekly data")
  let other = try parse(#"{"rateLimits":{"limitId":"other","primary":{"usedPercent":1,"windowDurationMins":300}},"rateLimitsByLimitId":{"other":{"primary":{"usedPercent":1,"windowDurationMins":300}}}}"#)
  check(other.fiveHour == nil, "other quota bucket never presented as Codex")
  let wrong = try parse(#"{"rateLimits":{"primary":{"usedPercent":1,"windowDurationMins":60}}}"#)
  check(wrong.fiveHour == nil, "other window never presented as five hours")
  check(QuotaWindow(usedPercent:120,windowDurationMins:300,resetsAt:nil).remaining == 0, "over-limit clamped")
  check(QuotaWindow(usedPercent:-2,windowDurationMins:300,resetsAt:nil).remaining == 100, "negative usage clamped")
  let missing = try parse(#"{"rateLimits":null,"rateLimitsByLimitId":null}"#)
  check(missing.fiveHour == nil, "missing values remain unknown")
 }
}
