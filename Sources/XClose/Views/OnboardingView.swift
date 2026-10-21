import SwiftUI
import XCloseCore

struct OnboardingView: View {
    let onFinish: () -> Void

    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var store: ApplicationPolicyStore
    @EnvironmentObject private var permissions: PermissionManager
    @StateObject private var step: ViewState<Int>

    init(onFinish: @escaping () -> Void, initialStep: Int = 0) {
        self.onFinish = onFinish
        _step = StateObject(wrappedValue: ViewState(initialStep))
    }

    private let stepCount = 3

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch step.value {
                case 0: welcome
                case 1: permission
                default: ready
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.horizontal, 40)
            .padding(.top, 44)

            Divider()
            HStack(spacing: 10) {
                HStack(spacing: 6) {
                    ForEach(0..<stepCount, id: \.self) { index in
                        Capsule()
                            .fill(index == step.value ? Color.accentColor : Color.secondary.opacity(0.3))
                            .frame(width: index == step.value ? 18 : 7, height: 7)
                    }
                }
                .accessibilityElement()
                .accessibilityLabel("Step \(step.value + 1) of \(stepCount)")
                Spacer()
                if step.value > 0 {
                    Button("Back") { step.value -= 1 }
                        .controlSize(.large)
                }
                Button(step.value < stepCount - 1 ? "Continue" : "Start Using XClose") {
                    if step.value < stepCount - 1 { step.value += 1 } else { finish() }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
        }
        .frame(width: 600, height: 540)
        .background(Color(nsColor: .windowBackgroundColor))
        .ignoresSafeArea()
    }

    private func header(title: String, subtitle: String) -> some View {
        VStack(spacing: 8) {
            Text(title).font(.largeTitle.weight(.bold))
            Text(subtitle)
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var welcome: some View {
        VStack(spacing: 22) {
            AppMark(size: 88)
            header(title: "Welcome to XClose", subtitle: "Make the red × quit the whole app, just like ⌘Q.")
            Card { BehaviorRows() }
            Text("XClose never force-quits. If an app asks to save and you cancel, it keeps running.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private var permission: some View {
        VStack(spacing: 22) {
            IconTile(symbol: "hand.raised.fill", color: .blue, size: 72)
            header(title: "Allow Accessibility",
                   subtitle: "XClose needs this to recognize a window's red × in other apps.")
            PermissionCard()
            Text("Click Allow, then turn on XClose in System Settings › Privacy & Security › Accessibility. This page updates by itself.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var ready: some View {
        VStack(spacing: 22) {
            IconTile(symbol: "checkmark", color: .green, size: 72)
            header(title: "You're all set",
                   subtitle: permissions.isAccessibilityTrusted
                       ? "XClose lives in the menu bar."
                       : "XClose will start as soon as Accessibility is allowed.")
            Card {
                CardRow {
                    RowLabel(title: "Pause anytime",
                             detail: "Use the XClose icon in the menu bar.",
                             symbol: "menubar.rectangle", color: .gray)
                }
                CardDivider()
                CardRow {
                    RowLabel(title: "Exclude apps",
                             detail: "Settings › Applications. Finder and system apps are always excluded.",
                             symbol: "nosign", color: .indigo)
                }
                CardDivider()
                CardRow {
                    RowLabel(title: "Close just one window",
                             detail: "Hold ⌥ Option while clicking red ×.",
                             symbol: "option", color: .blue)
                }
            }
        }
    }

    private func finish() {
        store.hasCompletedOnboarding = true
        store.isEnabled = true
        onFinish()
    }
}
