import SwiftUI
import XCloseCore

extension SettingsTab {
    var title: String {
        switch self {
        case .general: return "General"
        case .applications: return "Applications"
        case .permissions: return "Permissions"
        case .diagnostics: return "Diagnostics"
        case .about: return "About"
        }
    }

    var symbol: String {
        switch self {
        case .general: return "gearshape.fill"
        case .applications: return "square.grid.2x2.fill"
        case .permissions: return "hand.raised.fill"
        case .diagnostics: return "waveform.path.ecg"
        case .about: return "info"
        }
    }

    var color: Color {
        switch self {
        case .general: return .gray
        case .applications: return .indigo
        case .permissions: return .blue
        case .diagnostics: return .green
        case .about: return .gray
        }
    }
}

struct SettingsView: View {
    @ObservedObject var router: SettingsRouter
    @EnvironmentObject private var model: AppModel

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(width: 780, height: 560)
        .ignoresSafeArea()
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 2) {
            // Room for the window's traffic lights.
            Color.clear.frame(height: 44)
            ForEach(SettingsTab.allCases, id: \.self) { tab in
                SidebarItem(tab: tab, isSelected: router.tab == tab) { router.tab = tab }
            }
            Spacer()
            HStack(spacing: 8) {
                AppMark(size: 22)
                VStack(alignment: .leading, spacing: 0) {
                    Text("XClose").font(.caption.weight(.semibold))
                    Text(model.state.title).font(.caption2).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 14)
        }
        .padding(.horizontal, 10)
        .frame(width: 210)
        .frame(maxHeight: .infinity)
        .background(VisualEffectBackground(material: .sidebar))
    }

    @ViewBuilder
    private var content: some View {
        switch router.tab {
        case .general: GeneralSettingsView()
        case .applications: ApplicationsSettingsView()
        case .permissions: PermissionsSettingsView()
        case .diagnostics: DiagnosticsSettingsView()
        case .about: AboutSettingsView()
        }
    }
}

private struct SidebarItem: View {
    let tab: SettingsTab
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                IconTile(symbol: tab.symbol, color: tab.color, size: 22)
                Text(tab.title)
                    .foregroundStyle(isSelected ? Color.white : Color.primary)
                Spacer()
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(isSelected ? Color.accentColor : Color.clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Scrollable pane layout shared by all settings pages.
struct SettingsPane<Content: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                PaneHeader(title: title, subtitle: subtitle)
                content
            }
            .padding(.horizontal, 28)
            .padding(.top, 40)
            .padding(.bottom, 28)
        }
    }
}

struct GeneralSettingsView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var store: ApplicationPolicyStore
    @EnvironmentObject private var launchAtLogin: LaunchAtLoginManager
    @EnvironmentObject private var updates: UpdateManager

    var body: some View {
        SettingsPane(title: "General") {
            hero
            Card(title: "Behavior") {
                BehaviorRows()
                CardDivider()
                ToggleRow(title: "Hide apps instantly while they quit",
                          detail: "Windows disappear right away. If the app asks to save or confirm, it comes straight back.",
                          symbol: "bolt.fill", color: .orange, isOn: $store.hidesWhileQuitting)
            }
            Card(title: "Startup", footer: launchAtLogin.lastError) {
                ToggleRow(title: "Launch at login",
                          detail: "Start XClose automatically when you log in.",
                          symbol: "power", color: .gray,
                          isOn: Binding(get: { launchAtLogin.isEnabled || launchAtLogin.requiresApproval },
                                        set: { launchAtLogin.setEnabled($0) }))
                if launchAtLogin.requiresApproval {
                    CardDivider()
                    CardRow {
                        Text("Approve XClose in Login Items to finish.").foregroundStyle(.secondary)
                    } trailing: {
                        Button("Open Login Items") { launchAtLogin.openLoginItemsSettings() }
                    }
                }
            }
            if UpdateManager.isConfigured {
                Card(title: "Updates",
                     footer: "XClose checks piyushd23.github.io once a day for a newer version. No personal data is sent, and every update is verified with a signature before it is installed.") {
                    ToggleRow(title: "Check for updates automatically",
                              detail: "You'll see “Update Available” in the menu bar menu.",
                              symbol: "arrow.down.circle.fill", color: .teal,
                              isOn: Binding(get: { updates.automaticallyChecksForUpdates },
                                            set: { updates.automaticallyChecksForUpdates = $0 }))
                    CardDivider()
                    if let version = updates.pendingUpdateVersion {
                        CardRow {
                            RowLabel(title: "Version \(version) is ready to install",
                                     detail: "See what's new and install in one click.",
                                     symbol: "sparkles", color: .blue)
                        } trailing: {
                            Button("Install…") { updates.checkForUpdates() }
                                .buttonStyle(.borderedProminent)
                        }
                    } else {
                        CardRow {
                            Text("Version \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "–")")
                                .foregroundStyle(.secondary)
                        } trailing: {
                            Button("Check Now") { updates.checkForUpdates() }
                                .disabled(!updates.canCheckForUpdates)
                        }
                    }
                }
            }
        }
        .onAppear { launchAtLogin.refresh() }
    }

    /// Brand header: icon, live status and the main switch.
    private var hero: some View {
        HStack(spacing: 16) {
            AppMark(size: 60)
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text("XClose").font(.title3.weight(.bold)).foregroundStyle(.white)
                    heroStatus
                }
                Text(model.state.detail)
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.7))
                    .fixedSize(horizontal: false, vertical: true)
                if case .degraded = model.state {
                    Button("Try Again") { model.retryInterception() }
                        .controlSize(.small)
                }
            }
            Spacer()
            Toggle("Enable XClose", isOn: $store.isEnabled)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.large)
                .tint(Brand.lime)
        }
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Brand.ink))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.white.opacity(0.08)))
        .environment(\.colorScheme, .dark)
    }

    private var heroStatus: some View {
        let color: Color = model.state == .operational ? Brand.lime : model.state.tint
        return HStack(spacing: 5) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(model.state.title).font(.caption.weight(.semibold)).foregroundStyle(color)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 3)
        .background(Capsule().fill(color.opacity(0.16)))
    }
}

struct PermissionsSettingsView: View {
    @EnvironmentObject private var permissions: PermissionManager

    var body: some View {
        SettingsPane(title: "Permissions",
                     subtitle: "XClose needs one permission. Nothing leaves your Mac.") {
            PermissionCard()
            Card(title: "Troubleshooting",
                 footer: "macOS ties the permission to the app's signature, so this is needed after XClose is updated or rebuilt.") {
                CardRow {
                    RowLabel(title: "Allowed, but XClose still asks?",
                             detail: "Remove XClose from the Accessibility list with −, then add it again.")
                } trailing: {
                    Button("Open Settings") { permissions.openAccessibilitySettings() }
                }
            }
            Card(title: "Not used") {
                ForEach(Array(["Input Monitoring", "Screen Recording", "Automation", "Full Disk Access"].enumerated()), id: \.offset) { index, name in
                    if index > 0 { CardDivider() }
                    CardRow {
                        Text(name)
                    } trailing: {
                        Text("Not needed").foregroundStyle(.secondary)
                    }
                }
            }
        }
        .onAppear { permissions.refresh() }
    }
}

struct AboutSettingsView: View {
    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "dev"
        let build = info?["CFBundleVersion"] as? String ?? "0"
        return "Version \(short) (\(build))"
    }

    var body: some View {
        SettingsPane(title: "About") {
            VStack(spacing: 10) {
                AppMark(size: 112)
                Text("XClose").font(.title.weight(.bold))
                Text(version).foregroundStyle(.secondary)
                Text("Makes a window's red × quit its app, like ⌘Q.")
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            Card(title: "Privacy") {
                CardRow {
                    RowLabel(title: "Works entirely on your Mac",
                             detail: "No account and no analytics. The only network use is checking for updates, which you can turn off.",
                             symbol: "lock.fill", color: .blue)
                }
                CardDivider()
                CardRow {
                    RowLabel(title: "Reads only what it needs",
                             detail: "Never records keystrokes, window titles, document contents or browsing history.",
                             symbol: "eye.slash.fill", color: .gray)
                }
            }
        }
    }
}
