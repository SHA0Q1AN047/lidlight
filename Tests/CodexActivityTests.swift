import Foundation
@main struct ActivityTests {
 static func main() throws {
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { try? FileManager.default.removeItem(at: root) }
  let f = DateFormatter(); f.dateFormat="yyyy/MM/dd"
  let folder = root.appendingPathComponent("sessions/2025/01/01")
  try FileManager.default.createDirectory(at: folder, withIntermediateDirectories:true)
  let reader = CodexActivityReader(root:root)
  let file = folder.appendingPathComponent("a.jsonl")
  let iso = ISO8601DateFormatter(); iso.formatOptions=[.withInternetDateTime,.withFractionalSeconds]
  func event(_ name:String) -> Data {
   var data = try! JSONSerialization.data(withJSONObject:["type":"event_msg","timestamp":iso.string(from:Date()),"payload":["type":name]])
   data.append(10); return data
  }
  try event("task_started").write(to:file)
  assert(reader.running() == true)
  let h = try FileHandle(forWritingTo:file); try h.seekToEnd(); try h.write(contentsOf:event("task_complete")); try h.close()
  assert(reader.running() == false)
  let file2=folder.appendingPathComponent("b.jsonl")
  try event("task_started").write(to:file2); assert(reader.running(now: Date().addingTimeInterval(31)) == true)
  let h2 = try FileHandle(forWritingTo:file2); try h2.seekToEnd(); try h2.write(contentsOf:event("turn_aborted")); try h2.close(); assert(reader.running() == false)
  let resumed = folder.appendingPathComponent("resumed.jsonl")
  try event("task_started").write(to: resumed)
  reader.changed([resumed], rescan: false)
  assert(reader.running() == true) // old date folder discovered by event
  let resumedHandle = try FileHandle(forWritingTo: resumed)
  try resumedHandle.seekToEnd(); try resumedHandle.write(contentsOf: event("task_complete")); try resumedHandle.close()
  assert(reader.running() == false)
  let today = root.appendingPathComponent("sessions/" + f.string(from: Date()))
  try FileManager.default.createDirectory(at: today, withIntermediateDirectories: true)
  let newThread = today.appendingPathComponent("new.jsonl")
  try event("task_started").write(to: newThread)
  assert(reader.running() == true) // no 30-second discovery wait
  let latest = try FileHandle(forWritingTo: newThread)
  try latest.seekToEnd(); try latest.write(contentsOf: event("task_complete")); try latest.close()
  assert(reader.running() == false)
  print("Codex start, complete, concurrent sessions and abort passed")
 }
}
