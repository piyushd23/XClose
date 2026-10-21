import AppKit
import SwiftUI
import XCloseCore

/// The three facts every user must understand, used in onboarding and settings.
struct BehaviorRows: View {
    var body: some View {
        CardRow {
            RowLabel(title: "Red × quits the whole app",
                     detail: "All of its windows close, even if others are open. The app still asks to save unsaved work.",
                     symbol: "xmark", color: .red)
        }
        CardDivider()
        CardRow {
            RowLabel(title: "Option-click closes just the window",
                     detail: "Hold ⌥ Option while clicking red × to use the normal close.",
                     symbol: "option", color: .blue)
        }
        CardDivider()
        CardRow {
            RowLabel(title: "Everything else is unchanged",
                     detail: "Minimize, full screen and ⌘W work as before.",
                     symbol: "checkmark", color: .green)
        }
    }
}

struct AppIconView: View {
    let path: String?
    var size: CGFloat = 24

    var body: some View {
        Image(nsImage: icon)
            .resizable()
            .interpolation(.high)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }

    private var icon: NSImage {
        if let path, FileManager.default.fileExists(atPath: path) {
            return NSWorkspace.shared.icon(forFile: path)
        }
        return NSWorkspace.shared.icon(for: .applicationBundle)
    }
}

/// Accessibility status with the actions needed to fix it. Used in onboarding and Settings.
struct PermissionCard: View {
    @EnvironmentObject private var permissions: PermissionManager

    var body: some View {
        Card(footer: permissions.isAccessibilityTrusted ? nil :
                "XClose not in the list? Click + below the list and choose XClose, or drag it in from Finder.") {
            CardRow {
                RowLabel(title: "Accessibility",
                         detail: "Lets XClose recognize a window's red × and stop that click from closing the window.",
                         symbol: "hand.raised.fill", color: .blue)
            } trailing: {
                if permissions.isAccessibilityTrusted {
                    StatusPill(title: "Allowed", color: .green)
                } else {
                    Button("Allow…") { permissions.requestAccess() }
                        .buttonStyle(.borderedProminent)
                }
            }
            if !permissions.isAccessibilityTrusted {
                if !permissions.isInApplicationsFolder {
                    CardDivider()
                    CardRow {
                        Label("Move XClose to the Applications folder, reopen it, then allow access.",
                              systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                            .font(.callout)
                    }
                }
                CardDivider()
                CardRow {
                    HStack(spacing: 8) {
                        Button("Open System Settings") { permissions.openAccessibilitySettings() }
                        Button("Show in Finder") { permissions.revealAppInFinder() }
                    }
                    .controlSize(.small)
                } trailing: {
                    Button("Check Again") { permissions.refresh() }
                        .controlSize(.small)
                }
            }
        }
    }
}

/// View-local state holder. Used instead of `@State`, which the macOS 27 SDK
/// implements as a macro whose plugin ships only with Xcode; this keeps the
/// project buildable with the Command Line Tools as well.
final class ViewState<Value>: ObservableObject {
    @Published var value: Value
    init(_ value: Value) { self.value = value }
}
