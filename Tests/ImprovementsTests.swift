import Foundation

@main struct Tests {
 static func expect(_ value: Bool,_ label: String) { precondition(value,label) }
 static func main() {
  var cat = CatThermal()
  let now = Date(timeIntervalSince1970: 2_000_000_000)
  cat.update(high: true,now: now)
  cat.update(high: true,now: now.addingTimeInterval(14))
  expect(!cat.sweating,"Short thermal spike does not warn")
  cat.update(high: true,now: now.addingTimeInterval(15))
  expect(cat.sweating,"Sustained OS thermal pressure warns")
  cat.update(high: false,now: now.addingTimeInterval(16))
  expect(!cat.sweating && cat.since == nil,"Recovery clears warning")
  let suite = "com.lidlight.improvements-tests.\(UUID().uuidString)"
  let defaults = UserDefaults(suiteName: suite)!
  defer { defaults.removePersistentDomain(forName: suite) }
  let history = QuotaHistory(defaults: defaults)
  func window(_ used: Double, reset: Date? = nil) -> QuotaWindow { QuotaWindow(id:"primary",used:used,minutes:300,resetsAt:reset ?? now.addingTimeInterval(18000)) }
  history.record([window(10)],now:now)
  history.record([window(12)],now:now.addingTimeInterval(300))
  expect(history.trend(for:window(12),now:now.addingTimeInterval(300)) == nil,"No forecast from insufficient readings")
  history.record([window(15)],now:now.addingTimeInterval(600))
  let trend = history.trend(for:window(15),now:now.addingTimeInterval(600))!
  expect(trend.drop == 5 && trend.minutes == 10 && trend.perHour == 30,"Observed slope")
  expect(QuotaHistory(defaults:defaults).points.count == 3,"Local persistence")
  history.record([window(16)],now:now.addingTimeInterval(610))
  expect(history.points.count == 3,"Refresh spam is not independent evidence")
  expect(history.trend(for:window(1),now:now.addingTimeInterval(620)) == nil,"Decrease invalidates prior trend")
  expect(history.trend(for:window(15,reset:now.addingTimeInterval(36000)),now:now.addingTimeInterval(620)) == nil,"Reset window isolates readings")
  expect(history.trend(for:window(15),now:now.addingTimeInterval(2000)) == nil,"Stale trend hidden")
  history.record([window(1)],now:now.addingTimeInterval(900))
  expect(history.trend(for:window(1),now:now.addingTimeInterval(900)) == nil,"Quota refill restarts evidence")
  history.clear(); expect(history.points.isEmpty,"History can be cleared")
  let verification = InstallVerification(runningVersion:"1.6.0",defaults:defaults)
  defaults.set("1.6.0",forKey:"pendingUpdateVersion")
  verification.apply(InstallStatus(running:"1.6.0",installed:"1.6.0",service:nil,serviceRunning:true))
  expect(!verification.updateConfirmed,"An unverified service cannot confirm an update")
  verification.apply(InstallStatus(running:"1.5.0",installed:"1.6.0",service:"1.6.0",serviceRunning:true))
  expect(!verification.updateConfirmed && !verification.status!.verified,"Old running app is detected")
  verification.apply(InstallStatus(running:"1.6.0",installed:"1.6.0",service:"1.5.0",serviceRunning:true))
  expect(!verification.updateConfirmed,"Old service cannot confirm")
  verification.apply(InstallStatus(running:"1.6.0",installed:"1.6.0",service:"1.6.0",serviceRunning:false))
  expect(!verification.updateConfirmed,"Offline service cannot confirm")
  verification.apply(InstallStatus(running:"1.6.0",installed:"1.6.0",service:"1.6.0",serviceRunning:true))
  expect(verification.updateConfirmed && defaults.string(forKey:"pendingUpdateVersion") == nil,"Matching running app, installed app and live service confirms upgrade")
  print("PASS: sustained thermal state, local quota trends, evidence bounds, resets, stale data and honest upgrade confirmation")
 }
}
