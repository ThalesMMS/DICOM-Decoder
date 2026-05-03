import SwiftUI

@available(iOS 14.0, macOS 12.0, *)
struct SeriesNavigatorSliceShortcutButton: View {
    let index: Int
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        let fillColor = isSelected ? Color.accentColor.opacity(0.3) : Color.secondary.opacity(0.15)

        Button(action: onSelect) {
            ZStack {
                RoundedRectangle(cornerRadius: 4)
                    .fill(fillColor)
                    .frame(width: 50, height: 50)

                if isSelected {
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color.accentColor, lineWidth: 2)
                        .frame(width: 50, height: 50)
                }

                Image(systemName: "photo")
                    .foregroundColor(isSelected ? .primary : .secondary)
                    .font(.caption)
            }
        }
        .buttonStyle(PlainButtonStyle())
        .accessibilityLabel("Slice \(index + 1) shortcut")
        .accessibilityHint("Double tap to navigate to slice \(index + 1)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
