import AppKit
import SwiftUI
import XCloseCore

struct DiagnosticsSettingsView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var diagnostics: DiagnosticsStore
    @EnvironmentObject private var permissions: PermissionManager
    @StateObject private var probe = ViewState(ProbeState())

    struct ProbeState {
        var countdown: Int?
        var result: String?
        var succeeded = false
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    var body: some View {
        SettingsPane(title: "Diagnostics",
                     subtitle: "Kept in memory only and cleared when XClose quits.") {
            HStack(spacing: 10) {
                Metric(title: "Intercepted", value: "\(diagnostics.interceptedCount)")
                Metric(title: "Quit requested", value: "\(diagnostics.quitRequestedCount)")
                Metric(title: "Exited", value: "\(diagnostics.quitConfirmedCount)",
                       caption: diagnostics.quitNotConfirmedCount > 0 ? "\(diagnostics.quitNotConfirmedCount) still running" : nil)
                Metric(title: "Slowest check",
                       value: String(format: "%.0f ms", diagnostics.slowestDetectionMilliseconds),
                       caption: diagnostics.lastDetectionMilliseconds.map { String(format: "last %.1f ms", $0) })
            }

            Card(title: "Status") {
                CardRow { Text("XClose") } trailing: { StatusPill(state: model.state) }
                CardDivider()
                CardRow { Text("Click interceptor") } trailing: {
                    Text(Self.describe(model.tapStatus)).foregroundStyle(.secondary)
                }
                CardDivider()
                CardRow { Text("Interceptor timeouts") } trailing: {
                    Text("\(diagnostics.tapTimeoutCount)").foregroundStyle(.secondary)
                }
            }

            Card(title: "Test an app",
                 footer: "Nothing is closed or quit during a test.") {
                CardRow {
                    RowLabel(title: "Check a red ×",
                             detail: "Click Test, then hover over any app's red × within 3 seconds.",
                             symbol: "scope", color: .purple)
                } trailing: {
                    Button(probe.value.countdown.map { "Testing in \($0)…" } ?? "Test", action: startProbe)
                        .disabled(probe.value.countdown != nil || !permissions.isAccessibilityTrusted)
                }
                if let result = probe.value.result {
                    CardDivider()
                    CardRow {
                        Label(result, systemImage: probe.value.succeeded ? "checkmark.circle.fill" : "minus.circle.fill")
                            .foregroundStyle(probe.value.succeeded ? Color.green : Color.secondary)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Recent events")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Copy Report", action: copyReport).controlSize(.small)
                    Button("Clear") { diagnostics.clear() }.controlSize(.small)
                }
                .padding(.leading, 4)
                Card {
                    let events = Array(diagnostics.events.elements.suffix(50).reversed())
                    if events.isEmpty {
                        CardRow { Text("No events yet").foregroundStyle(.secondary) }
                    }
                    ForEach(Array(events.enumerated()), id: \.element.id) { index, event in
                        if index > 0 { CardDivider() }
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text(Self.timeFormatter.string(from: event.date))
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                            Text(event.kind.rawValue).fontWeight(.medium)
                            Text(event.detail).foregroundStyle(.secondary).lineLimit(2)
                            Spacer(minLength: 0)
                        }
                        .font(.callout)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                    }
                }
            }
        }
    }

    private func copyReport() {
        let report = diagnostics.report(state: model.state, tapStatus: model.tapStatus,
                                        trusted: permissions.isAccessibilityTrusted)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(report, forType: .string)
    }

    private func startProbe() {
        probe.value = ProbeState(countdown: 3, result: nil)
        tick()
    }

    private func tick() {
        guard let remaining = probe.value.countdown else { return }
        if remaining == 0 {
            probe.value.countdown = nil
            model.testPointerTarget { [probe] evaluation in
                probe.value.result = Self.describe(evaluation)
                if case .success = evaluation.result { probe.value.succeeded = true }
            }
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            probe.value.countdown = remaining - 1
            tick()
        }
    }

    private static func describe(_ status: TapStatus) -> String {
        switch status {
        case .stopped: return "Off"
        case .starting: return "Starting"
        case .running: return "Running"
        case .failedToStart: return "Could not start"
        case .unstable: return "Paused after repeated timeouts"
        }
    }

    private static func describe(_ evaluation: ClickEvaluation) -> String {
        let app = evaluation.appName ?? evaluation.pid.map { "pid \($0)" } ?? "No app"
        let timing = String(format: "%.1f ms", evaluation.elapsedMilliseconds)
        switch evaluation.result {
        case .success:
            return "\(app): red × recognized in \(timing). Clicking it would quit \(app)."
        case .failure(let reason):
            return "\(app): \(reason.summary) (\(timing)). A click here behaves normally."
        }
    }
}

private struct Metric: View {
    let title: String
    let value: String
    var caption: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title2.weight(.semibold)).monospacedDigit()
            Text(caption ?? " ").font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
            .strokeBorder(Color(nsColor: .separatorColor).opacity(0.6)))
    }
}
