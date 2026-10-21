import AppKit
import SwiftUI
import UniformTypeIdentifiers
import XCloseCore

struct ApplicationsSettingsView: View {
    @EnvironmentObject private var store: ApplicationPolicyStore
    @EnvironmentObject private var lifecycle: ApplicationLifecycleMonitor
    @StateObject private var searchState = ViewState("")
    private var search: String { searchState.value }

    /// Running regular apps only; no scan of installed apps is needed. Other apps
    /// can be added with "Add Application…".
    private var runningApps: [AppDescriptor] {
        let policy = ApplicationPolicy(ownBundleID: Bundle.main.bundleIdentifier,
                                       ownPID: ProcessInfo.processInfo.processIdentifier)
        var seen = Set<AppKey>()
        return lifecycle.apps.values
            .filter { app in
                guard let key = app.key, !store.isExcluded(key), seen.insert(key).inserted else { return false }
                return policy.eligibility(of: app) == .eligible
            }
            .filter(matchesSearch)
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var excluded: [ExclusionEntry] {
        store.exclusions.filter {
            search.isEmpty || $0.displayName.localizedCaseInsensitiveContains(search)
                || $0.key.description.localizedCaseInsensitiveContains(search)
        }
    }

    var body: some View {
        SettingsPane(title: "Applications",
                     subtitle: "Choose apps whose red × should keep closing just the window.") {
            HStack(spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Search", text: $searchState.value).textFieldStyle(.plain)
                    if !search.isEmpty {
                        Button { searchState.value = "" } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Clear search")
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor)))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color(nsColor: .separatorColor).opacity(0.6)))
                Button("Add Application…", action: chooseApplication)
            }

            Card(title: "Excluded", footer: "Red × closes the window normally in these apps.") {
                if excluded.isEmpty {
                    CardRow { Text(search.isEmpty ? "No excluded apps" : "No matches").foregroundStyle(.secondary) }
                }
                ForEach(Array(excluded.enumerated()), id: \.element.id) { index, entry in
                    if index > 0 { CardDivider() }
                    CardRow {
                        HStack(spacing: 10) {
                            AppIconView(path: entry.path, size: 28)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(entry.displayName)
                                Text(entry.key.description).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    } trailing: {
                        Button("Remove") { store.removeExclusion(entry.key) }
                    }
                }
            }

            Card(title: "Running apps",
                 footer: "Always excluded: Finder, the Dock, the menu bar and other system components, background and menu-bar-only apps, and XClose itself.") {
                if runningApps.isEmpty {
                    CardRow { Text(search.isEmpty ? "No other running apps" : "No matches").foregroundStyle(.secondary) }
                }
                ForEach(Array(runningApps.enumerated()), id: \.element.pid) { index, app in
                    if index > 0 { CardDivider() }
                    CardRow {
                        HStack(spacing: 10) {
                            AppIconView(path: app.bundlePath, size: 28)
                            Text(app.name)
                        }
                    } trailing: {
                        Button("Exclude") { store.exclude(app) }
                    }
                }
            }
        }
    }

    private func matchesSearch(_ app: AppDescriptor) -> Bool {
        search.isEmpty || app.name.localizedCaseInsensitiveContains(search)
            || (app.bundleID?.localizedCaseInsensitiveContains(search) ?? false)
    }

    private func chooseApplication() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.applicationBundle]
        panel.allowsMultipleSelection = true
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.prompt = "Exclude"
        guard panel.runModal() == .OK else { return }
        for url in panel.urls { store.exclude(appAt: url) }
    }
}
