import SwiftUI

struct GlassPillBadge: View {
    let text: String
    var systemImage: String? = nil
    var tint: Color? = nil

    var body: some View {
        HStack(spacing: 4) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.caption2.weight(.semibold))
            }
            Text(text)
                .font(.caption2.weight(.semibold))
        }
        .foregroundStyle(.primary)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .glassEffect(
            tint.map { Glass.regular.tint($0.opacity(0.25)) } ?? .regular,
            in: Capsule()
        )
    }
}

struct GlassIconButton: View {
    let systemImage: String
    let accessibilityLabel: String
    let isDisabled: Bool
    let action: () -> Void

    init(
        systemImage: String,
        accessibilityLabel: String,
        isDisabled: Bool = false,
        action: @escaping () -> Void
    ) {
        self.systemImage = systemImage
        self.accessibilityLabel = accessibilityLabel
        self.isDisabled = isDisabled
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 26, height: 26)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.4 : 1.0)
        .glassEffect(.regular.interactive(), in: Circle())
        .accessibilityLabel(accessibilityLabel)
    }
}
