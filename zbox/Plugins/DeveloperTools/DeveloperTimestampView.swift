import SwiftUI

struct DeveloperTimestampView: View {
    @Bindable var session: DeveloperTimestampSession
    let copy: (String) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Picker("Direction", selection: $session.fromDate) {
                    Text("Timestamp to Date").tag(false)
                    Text("Date to Timestamp").tag(true)
                }.pickerStyle(.segmented)
                if !session.fromDate {
                    Picker("Input Unit", selection: $session.unit) {
                        ForEach(TimestampConverter.Unit.allCases, id: \.self) { unit in
                            Text(unit.title).tag(unit)
                        }
                    }.fixedSize()
                }
                Text(session.fromDate
                     ? String(localized: "Include Z or an explicit offset such as +08:00. Precision: up to milliseconds.")
                     : String(localized: "Units are explicit. Negative timestamps are supported."))
                    .font(.caption).foregroundStyle(.secondary)
                PlainTextEditor(text: $session.input, label: String(localized: "Timestamp Input"))
                    .frame(height: 64)
                HStack {
                    Button("Current Time") { session.useCurrentTime() }
                    Button("Clear") { session.input = "" }
                    Spacer()
                    Button("Convert") { session.run() }
                        .keyboardShortcut(.return, modifiers: .command)
                }
                if let error = session.error {
                    Text(error).foregroundStyle(.red).textSelection(.enabled)
                }
                if let result = session.result {
                    Divider()
                    resultRow(String(localized: "Seconds"), value: result.seconds)
                    resultRow(String(localized: "Milliseconds"), value: String(result.milliseconds))
                    resultRow("UTC", value: result.utc)
                    resultRow(String(localized: "Local Time") + " · " + result.localTimeZone, value: result.local)
                    Button("Copy Result") {
                        copy(session.fromDate ? result.seconds : result.utc)
                    }
                    .keyboardShortcut("c", modifiers: [.command, .shift])
                    Text("Copy Result copies UTC for timestamp input, or seconds for date input.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func resultRow(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            HStack(alignment: .top) {
                Text(value).font(.system(.body, design: .monospaced)).textSelection(.enabled)
                Spacer()
                Button("Copy") { copy(value) }.accessibilityLabel(String(localized: "Copy \(title)"))
            }
        }
    }
}
