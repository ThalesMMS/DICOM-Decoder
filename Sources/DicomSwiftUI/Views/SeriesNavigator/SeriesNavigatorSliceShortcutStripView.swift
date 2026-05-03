import SwiftUI

@available(iOS 14.0, macOS 12.0, *)
struct SeriesNavigatorSliceShortcutStripView: View {
    @ObservedObject var navigatorViewModel: SeriesNavigatorViewModel

    var body: some View {
        VStack(spacing: 4) {
            Text("Slices")
                .font(.caption2)
                .foregroundColor(.secondary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    let visibleRange = sliceShortcutVisibleRange

                    if visibleRange.lowerBound > 0 {
                        Text("... \(visibleRange.lowerBound) earlier")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 8)
                    }

                    ForEach(visibleRange, id: \.self) { index in
                        SeriesNavigatorSliceShortcutButton(
                            index: index,
                            isSelected: index == navigatorViewModel.currentIndex,
                            onSelect: { navigatorViewModel.goToIndex(index) }
                        )
                    }

                    let hiddenAfter = max(0, navigatorViewModel.totalCount - visibleRange.upperBound)
                    if hiddenAfter > 0 {
                        Text("... +\(hiddenAfter) more")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 8)
                    }
                }
            }
            .frame(height: 60)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Slice shortcut strip")
        .accessibilityHint("Quick navigation for series slices")
    }

    private var sliceShortcutVisibleRange: Range<Int> {
        let totalCount = navigatorViewModel.totalCount
        let maxVisibleCount = 10
        guard totalCount > 0 else {
            return 0..<0
        }

        let preferredStart = max(0, navigatorViewModel.currentIndex - 4)
        let latestStart = max(0, totalCount - maxVisibleCount)
        let start = min(preferredStart, latestStart)
        let end = min(totalCount, start + maxVisibleCount)
        return start..<end
    }
}
