import SwiftUI

struct FeaturePages: View {
    @ObservedObject var features: Features
    private let mint = Color(red: 0.48, green: 0.93, blue: 0.78)
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(features.page.capitalized).font(.system(size: 28, weight: .semibold, design: .rounded))
            if features.page == "sessions" { sessions }
            if features.page == "rules" { rules }
            if features.page == "settings" { settings }
            if features.page == "activity" { activity }
            if let message = features.message { Text(message).foregroundColor(.orange).fixedSize(horizontal: false, vertical: true) }
        }.font(.system(size: 12)).frame(maxWidth: .infinity, alignment: .leading)
    }
    private var sessions: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(features.sessionText).foregroundColor(mint)
            HStack {
                Button("Screen off") { features.blankScreen(lock: false) }
                Button("Lock & run") { features.blankScreen(lock: true) }
                Button("Restore light") { features.restore() }
            }
            Text("Screen off uses macOS display sleep and may lock. Lock & run locks your session while keeping work active.").foregroundColor(.gray)
            Divider()
            Text("Keep awake for").fontWeight(.semibold)
            HStack {
                ForEach([30, 60, 120], id: \.self) { minutes in
                    Button("\(minutes)m") { features.begin(until: Date().addingTimeInterval(Double(minutes * 60))) }
                }
            }
            HStack {
                TextField("Minutes", value: $features.duration, formatter: NumberFormatter()).frame(width: 80)
                Button("Start timer") { features.begin(until: Date().addingTimeInterval(Double(features.duration) * 60)) }
            }
            Divider()
            DatePicker("Stay awake until", selection: $features.until, in: Date()...Date().addingTimeInterval(7 * 86400), displayedComponents: [.date, .hourAndMinute])
            Button("Start until selected time") { features.begin(until: features.until) }
            Divider()
            Button { features.oneShot() } label: { Label("One-shot awake", systemImage: "sparkles") }
            Text("Ends on unplug or next login. Restores the previous mode.").foregroundColor(.gray)
            Button { features.oneShot(presentation: true) } label: { Label("Start presentation", systemImage: "display") }
            Text("Keeps the display awake too. End it here when finished.").foregroundColor(.gray)
            Divider()
            Text("Wait for a process").fontWeight(.semibold)
            HStack {
                TextField("Process ID (PID)", text: $features.processInput)
                Button("Wait") { features.watchProcess() }
            }
            Text("Choose a process you own. Restores sleep mode when it exits, with a seven-day safety limit. Lidlight must stay open.").foregroundColor(.gray)
            Button("End active session") { features.stopSession() }.foregroundColor(mint)
        }.textFieldStyle(.roundedBorder)
    }
    private var rules: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Manual Allow sleep pauses these rules. Choose Automatic to resume.").foregroundColor(.gray)
            Toggle("Awake when an external display is connected", isOn: preference(\.displayRule))
            Divider()
            Text("App rules").fontWeight(.semibold)
            Text("Stay awake while any selected App is running.").foregroundColor(.gray)
            ForEach(features.preferences.apps) { app in
                HStack { Text(app.name); Spacer(); Button { features.removeApp(app.id) } label: { Image(systemName: "minus.circle") }.buttonStyle(.plain).accessibilityLabel("Remove " + app.name) }
            }
            Button("Choose App…") { features.chooseApp() }
            Divider()
            Toggle("Awake schedule", isOn: preference(\.schedule))
            Toggle("Weekdays only", isOn: preference(\.weekdays)).disabled(!features.preferences.schedule)
            HStack {
                DatePicker("From", selection: scheduleTime(\.start), displayedComponents: .hourAndMinute)
                DatePicker("To", selection: scheduleTime(\.end), displayedComponents: .hourAndMinute)
            }.disabled(!features.preferences.schedule)
            Text("Equal start/end times disable the schedule. Uses local time; overnight ranges are supported. Outside the schedule your manual base mode returns. Lidlight must stay open.").foregroundColor(.gray)
        }
    }
    private var settings: some View {
        VStack(alignment: .leading, spacing: 16) {
            Toggle("Launch at login", isOn: Binding(get: { features.preferences.launchAtLogin }, set: features.setLogin))
            Toggle("Always return to Automatic on service restart", isOn: preference(\.startupAuto))
            Text("When off, the last mode is restored after restarting.").foregroundColor(.gray)
            Divider()
            Toggle("Only stay awake on AC power", isOn: preference(\.acOnly))
            Picker("Battery protection", selection: preference(\.threshold)) {
                ForEach([10, 15, 20, 25, 30, 40, 50], id: \.self) { Text("\($0)%").tag($0) }
            }
            Toggle("Low-battery notification", isOn: Binding(get: { features.preferences.notifications }, set: features.setNotifications))
            Text("Warns five percentage points before protection. Permission is requested only when enabled.").foregroundColor(.gray)
            Divider()
            Toggle("Global shortcut", isOn: preference(\.shortcut))
            Picker("Toggle awake / sleep", selection: preference(\.shortcutKey)) {
                Text("⌘⌥L").tag(0); Text("⌘⌥⇧L").tag(1)
            }.disabled(!features.preferences.shortcut)
            Toggle("Show timer beside menu icon", isOn: preference(\.countdown))
            Divider()
            Text(features.batteryText).foregroundColor(.gray)
            Text("Measured as percentage-point drops while awake on battery, not energy or battery-life prediction.").font(.system(size: 10)).foregroundColor(.gray)
        }
    }
    private var activity: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("The latest 40 local events. Nothing is uploaded.").foregroundColor(.gray)
            if features.history.isEmpty { Text("No activity yet.") }
            ForEach(Array(features.history.enumerated()), id: \.offset) { _, event in Text(event).font(.system(size: 11, design: .monospaced)).fixedSize(horizontal: false, vertical: true) }
            Button("Clear local history") { features.clearHistory() }
        }
    }
    private func preference<Value>(_ key: WritableKeyPath<Preferences, Value>) -> Binding<Value> {
        Binding(get: { features.preferences[keyPath: key] }, set: { features.preferences[keyPath: key] = $0; features.applyPreferences() })
    }
    private func scheduleTime(_ key: WritableKeyPath<Preferences, Int>) -> Binding<Date> {
        Binding(get: {
            Calendar.current.startOfDay(for: Date()).addingTimeInterval(Double(features.preferences[keyPath: key] * 60))
        }, set: { date in
            features.preferences[keyPath: key] = Calendar.current.component(.hour, from: date) * 60 + Calendar.current.component(.minute, from: date)
            features.applyPreferences()
        })
    }
}
