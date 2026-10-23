import SwiftUI

/// A titled group of rows: a small uppercase heading, then the rows.
struct SettingsGroup<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(title.uppercased())
                .font(.caption.weight(.semibold))
                .tracking(0.6)
                .foregroundStyle(.secondary)
            content
        }
    }
}

/// Title and description on the left, the control on the right.
struct SettingsRow<Control: View>: View {
    let title: String
    var description: String?
    /// Marks the layer that's active right now.
    var isActive = false
    @ViewBuilder var control: Control

    var body: some View {
        HStack(alignment: .center, spacing: 24) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(title)
                        .font(.body.weight(.medium))
                    if isActive {
                        Image(systemName: "circle.fill")
                            .font(.system(size: 7))
                            .foregroundStyle(.green)
                            .help("Active now")
                    }
                }
                if let description {
                    Text(description)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
            control
        }
    }
}

/// A longer explanation under a group.
struct SettingsNote: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// A sidebar entry; the selected one gets a rounded highlight.
struct SettingsSidebarItem: View {
    let title: String
    let systemImage: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .frame(width: 20)
                Text(title)
                Spacer(minLength: 0)
            }
            .font(.body.weight(isSelected ? .medium : .regular))
            .foregroundStyle(isSelected ? .primary : .secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? Color.primary.opacity(0.09) : .clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
