import AppKit
import SwiftUI
import XCloseCore

/// Brand colors from the app icon. Lime is used as a fill behind dark content,
/// never as text on light backgrounds, where it would be unreadable.
enum Brand {
    static let lime = Color(red: 0.86, green: 0.98, blue: 0.24)
    static let ink = Color(red: 0.05, green: 0.05, blue: 0.06)
}

extension OperationalState {
    var tint: Color {
        switch self {
        case .operational: return .green
        case .paused, .starting: return .secondary
        case .permissionRequired: return .orange
        case .degraded: return .red
        }
    }

    var detail: String {
        switch self {
        case .operational: return "Clicking red × quits the app."
        case .paused: return "Red × closes windows as usual."
        case .starting: return "Getting ready…"
        case .permissionRequired: return "Allow Accessibility access to turn XClose on."
        case .degraded(let reason): return reason.summary
        }
    }
}

/// Rounded, colored square holding a white symbol, as in System Settings.
struct IconTile: View {
    let symbol: String
    let color: Color
    var size: CGFloat = 22

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.52, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(RoundedRectangle(cornerRadius: size * 0.26, style: .continuous).fill(color.gradient))
            .accessibilityHidden(true)
    }
}

struct StatusPill: View {
    let title: String
    let color: Color

    init(state: OperationalState) {
        title = state.title
        color = state.tint
    }

    init(title: String, color: Color) {
        self.title = title
        self.color = color
    }

    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(title).font(.caption.weight(.semibold))
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(Capsule().fill(color.opacity(0.14)))
        .accessibilityElement(children: .combine)
    }
}

/// Large pane title with an optional one-line explanation.
struct PaneHeader: View {
    let title: String
    var subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.title2.weight(.bold))
            if let subtitle {
                Text(subtitle).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A grouped container of rows, matching macOS grouped forms.
struct Card<Content: View>: View {
    var title: String?
    var footer: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let title {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 4)
            }
            VStack(alignment: .leading, spacing: 0) { content }
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor)))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color(nsColor: .separatorColor).opacity(0.6)))
            if let footer {
                Text(footer)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// One row in a Card: leading content, optional trailing accessory.
struct CardRow<Leading: View, Trailing: View>: View {
    @ViewBuilder var leading: Leading
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            leading
            Spacer(minLength: 8)
            trailing
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(minHeight: 44)
    }
}

extension CardRow where Trailing == EmptyView {
    init(@ViewBuilder leading: () -> Leading) {
        self.leading = leading()
        self.trailing = EmptyView()
    }
}

struct CardDivider: View {
    var body: some View { Divider().padding(.leading, 14) }
}

/// Title with a secondary explanation, used as the leading part of rows.
struct RowLabel: View {
    let title: String
    var detail: String?
    var symbol: String?
    var color: Color = .gray

    var body: some View {
        HStack(spacing: 10) {
            if let symbol { IconTile(symbol: symbol, color: color, size: 26) }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                if let detail {
                    Text(detail)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

/// A row with a switch on the trailing edge.
struct ToggleRow: View {
    let title: String
    var detail: String?
    var symbol: String?
    var color: Color = .gray
    @Binding var isOn: Bool

    var body: some View {
        CardRow {
            RowLabel(title: title, detail: detail, symbol: symbol, color: color)
        } trailing: {
            Toggle(title, isOn: $isOn).labelsHidden().toggleStyle(.switch)
        }
    }
}

/// Sidebar and window chrome material.
struct VisualEffectBackground: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .sidebar

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = .behindWindow
        view.state = .followsWindowActiveState
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
    }
}

/// The app's own icon, for headers.
struct AppMark: View {
    var size: CGFloat = 64

    var body: some View {
        Image(nsImage: NSApp.applicationIconImage)
            .resizable()
            .interpolation(.high)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

extension NSFont {
    var bold: NSFont { NSFontManager.shared.convert(self, toHaveTrait: .boldFontMask) }
}
