//
//  SeriesNavigatorView.swift
//
//  SwiftUI view for navigating through DICOM series slices
//
//  This view provides a complete interface for navigating through a series of
//  DICOM images (slices) with multiple interaction modes: sequential navigation
//  via buttons, direct navigation via slider, and jump to first/last.
//
//  The view integrates with SeriesNavigatorViewModel for state management and
//  provides callbacks for navigation events so you can update the displayed
//  image accordingly. It supports both compact and expanded layouts for
//  different UI contexts.
//
//  Platform Availability:
//
//  Available on iOS 14+, macOS 12+, and all platforms supporting SwiftUI.
//  Uses native SwiftUI components for optimal performance and platform integration.
//
//  Accessibility:
//
//  All interactive controls include proper accessibility labels, hints, and values
//  for VoiceOver support. Navigation state is announced dynamically.
//

import SwiftUI
import Combine
import DicomCore

/// A SwiftUI view for navigating through DICOM series slices.
///
/// ## Overview
///
/// ``SeriesNavigatorView`` provides a comprehensive control panel for navigating through
/// a series of DICOM images (slices). It offers multiple interaction modes including
/// sequential navigation buttons, direct navigation via slider, jump-to-first/last
/// buttons.
///
/// The view is designed to work with ``SeriesNavigatorViewModel`` for state management
/// and provides callbacks when navigation occurs so you can update the displayed image.
/// It supports both compact and expanded layouts for different UI contexts.
///
/// **Key Features:**
/// - Previous/Next navigation buttons
/// - Slice counter display (e.g., "3 / 150")
/// - Interactive slider for direct navigation
/// - First/Last jump buttons
/// - Thumbnail strip placeholder for future enhancement
/// - Customizable layout (compact or expanded)
/// - Dark mode support
/// - Full accessibility support for VoiceOver
///
/// **Control Layout:**
/// - First/Previous/Next/Last buttons
/// - Current position indicator (e.g., "25 / 150")
/// - Slider for direct slice selection
/// - Progress percentage display
///
/// ## Usage
///
/// Basic usage with default layout:
///
/// ```swift
/// struct SeriesViewer: View {
///     @StateObject private var navigatorVM = SeriesNavigatorViewModel()
///     @StateObject private var imageVM = DicomImageViewModel()
///     let seriesURLs: [URL]
///
///     var body: some View {
///         VStack {
///             // Display current image
///             DicomImageView(viewModel: imageVM)
///
///             // Navigation controls
///             SeriesNavigatorView(
///                 navigatorViewModel: navigatorVM,
///                 onNavigate: { url in
///                     Task {
///                         await imageVM.loadImage(from: url)
///                     }
///                 }
///             )
///         }
///         .onAppear {
///             navigatorVM.setSeriesURLs(seriesURLs)
///             if let firstURL = navigatorVM.currentURL {
///                 Task {
///                     await imageVM.loadImage(from: firstURL)
///                 }
///             }
///         }
///     }
/// }
/// ```
///
/// Compact layout for embedded use:
///
/// ```swift
/// SeriesNavigatorView(
///     navigatorViewModel: navigatorVM,
///     layout: .compact,
///     onNavigate: { url in
///         Task {
///             await imageVM.loadImage(from: url)
///         }
///     }
/// )
/// .padding()
/// .background(Color.secondary.opacity(0.1))
/// .cornerRadius(8)
/// ```
///
/// ## Topics
///
/// ### Creating a View
///
/// - ``init(navigatorViewModel:layout:onNavigate:)``
///
/// ### Layout Options
///
/// - ``Layout``
///
/// ### Customization
///
/// Apply standard SwiftUI modifiers for styling:
/// - `.padding()` - Add padding around controls
/// - `.background()` - Add background color
/// - `.cornerRadius()` - Round corners
/// - `.disabled()` - Disable all controls
///
@available(iOS 14.0, macOS 12.0, *)
public struct SeriesNavigatorView: View {

    // MARK: - Layout Options

    /// Layout style for the series navigator control panel.
    ///
    /// Controls the visual density and spacing of the navigation interface. Use
    /// expanded layout for primary navigation controls and compact layout for
    /// embedded or space-constrained contexts.
    ///
    /// ## Usage
    ///
    /// ```swift
    /// // Full layout for main navigator
    /// SeriesNavigatorView(
    ///     navigatorViewModel: viewModel,
    ///     layout: .expanded
    /// )
    ///
    /// // Compact layout for embedded control
    /// SeriesNavigatorView(
    ///     navigatorViewModel: viewModel,
    ///     layout: .compact
    /// )
    /// ```
    public enum Layout {
        /// Full layout with all controls and labels.
        ///
        /// Provides standard spacing (16pt), full-size fonts (.title2, .headline),
        /// labeled buttons, progress percentage, and thumbnail strip. Best for primary
        /// navigation contexts where space is not constrained.
        case expanded

        /// Compact layout for embedded use.
        ///
        /// Uses smaller spacing (12pt), reduced fonts (.title3, .body), icon-only
        /// buttons, and no thumbnail strip. Ideal for toolbars, sidebars, or embedded
        /// contexts where space is limited.
        case compact
    }

    // MARK: - Properties

    /// View model managing navigation state
    @ObservedObject private var navigatorViewModel: SeriesNavigatorViewModel

    /// Layout style for the control panel
    private let layout: Layout

    /// Callback when navigation occurs (provides new current URL)
    private let onNavigate: ((URL) -> Void)?

    // Local state for slider editing
    @State private var isEditingSlider = false
    @State private var tempSliderValue: Double

    // MARK: - Initializers

    /// Creates a series navigator view.
    ///
    /// Provides a complete control panel for navigating through DICOM series with buttons
    /// and slider. The view observes the provided view model
    /// for state changes and calls the navigation callback when the current image changes.
    ///
    /// - Parameters:
    ///   - navigatorViewModel: View model managing navigation state
    ///   - layout: Layout style (`.expanded` or `.compact`). Defaults to `.expanded`
    ///   - onNavigate: Optional callback when navigation occurs, provides current URL
    ///
    /// ## Example
    ///
    /// ```swift
    /// @StateObject private var navigatorVM = SeriesNavigatorViewModel()
    /// @StateObject private var imageVM = DicomImageViewModel()
    ///
    /// SeriesNavigatorView(
    ///     navigatorViewModel: navigatorVM,
    ///     onNavigate: { url in
    ///         Task {
    ///             await imageVM.loadImage(from: url)
    ///         }
    ///     }
    /// )
    /// ```
    ///
    public init(
        navigatorViewModel: SeriesNavigatorViewModel,
        layout: Layout = .expanded,
        onNavigate: ((URL) -> Void)? = nil
    ) {
        self.navigatorViewModel = navigatorViewModel
        self.layout = layout
        self.onNavigate = onNavigate

        // Initialize temp slider value with current index
        _tempSliderValue = State(initialValue: Double(navigatorViewModel.currentIndex))
    }

    // MARK: - Body

    public var body: some View {
        VStack(spacing: layout == .compact ? 12 : 16) {
            // Position indicator
            positionIndicatorView

            // Navigation buttons
            navigationButtonsView

            // Slider
            if !navigatorViewModel.isEmpty {
                sliderView
            }

            // Thumbnail strip placeholder
            if layout == .expanded && !navigatorViewModel.isEmpty {
                thumbnailStripView
            }
        }
        .padding(layout == .compact ? 12 : 16)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Series navigation controls")
        .onChangeCompat(
            of: navigatorViewModel.currentIndex,
            fallback: navigatorViewModel.$currentIndex
        ) { newIndex in
            // Sync temp slider value when view model changes externally
            if !isEditingSlider {
                tempSliderValue = Double(newIndex)
            }

            // Notify callback of navigation
            if let currentURL = navigatorViewModel.currentURL {
                onNavigate?(currentURL)
            }
        }
    }

    // MARK: - Position Indicator View

    /// Position indicator showing current slice and total count.
    ///
    /// Displays the current position in the series (e.g., "25 / 150") with large,
    /// monospaced digits for readability. In expanded layout, also shows progress
    /// percentage. Displays "No Series Loaded" message when the series is empty.
    private var positionIndicatorView: some View {
        VStack(spacing: 4) {
            if navigatorViewModel.isEmpty {
                Text("No Series Loaded")
                    .font(layout == .compact ? .caption : .headline)
                    .foregroundColor(.secondary)
                    .accessibilityLabel("No series loaded")
            } else {
                Text(navigatorViewModel.positionString)
                    .font(layout == .compact ? .title3 : .title2)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                    .monospacedDigit()
                    .accessibilityLabel("Slice \(navigatorViewModel.currentIndex + 1) of \(navigatorViewModel.totalCount)")

                if layout == .expanded {
                    Text("\(Int(navigatorViewModel.progressPercentage * 100))% complete")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .accessibilityLabel("\(Int(navigatorViewModel.progressPercentage * 100)) percent complete")
                }
            }
        }
    }

    // MARK: - Navigation Buttons View

    /// Navigation buttons (First, Previous, Next, Last).
    ///
    /// Provides four navigation buttons with appropriate styling and enabled states:
    /// - **First**: Jumps to first slice (disabled when at first slice)
    /// - **Previous**: Goes to previous slice (prominent style, disabled when can't go back)
    /// - **Next**: Goes to next slice (prominent style, disabled when can't go forward)
    /// - **Last**: Jumps to last slice (disabled when at last slice)
    ///
    /// In compact layout, buttons show icons only. In expanded layout, buttons include
    /// text labels for clarity.
    private var navigationButtonsView: some View {
        HStack(spacing: layout == .compact ? 8 : 12) {
            // First button
            Button(action: {
                navigatorViewModel.goToFirst()
            }) {
                Label(
                    layout == .compact ? "" : "First",
                    systemImage: "backward.end.fill"
                )
                .font(layout == .compact ? .body : .headline)
                .frame(minWidth: layout == .compact ? 0 : 60)
            }
            .buttonStyle(.bordered)
            .disabled(navigatorViewModel.isEmpty || navigatorViewModel.isAtFirst)
            .accessibilityLabel("First slice")
            .accessibilityHint("Jump to first slice in series")

            // Previous button
            Button(action: {
                navigatorViewModel.goToPrevious()
            }) {
                Label(
                    layout == .compact ? "" : "Previous",
                    systemImage: "chevron.left"
                )
                .font(layout == .compact ? .body : .headline)
                .frame(minWidth: layout == .compact ? 0 : 80)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!navigatorViewModel.canGoPrevious)
            .accessibilityLabel("Previous slice")
            .accessibilityHint("Go to previous slice")

            Spacer()

            // Next button
            Button(action: {
                navigatorViewModel.goToNext()
            }) {
                Label(
                    layout == .compact ? "" : "Next",
                    systemImage: "chevron.right"
                )
                .font(layout == .compact ? .body : .headline)
                .labelStyle(.trailingIcon)
                .frame(minWidth: layout == .compact ? 0 : 80)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!navigatorViewModel.canGoNext)
            .accessibilityLabel("Next slice")
            .accessibilityHint("Go to next slice")

            // Last button
            Button(action: {
                navigatorViewModel.goToLast()
            }) {
                Label(
                    layout == .compact ? "" : "Last",
                    systemImage: "forward.end.fill"
                )
                .font(layout == .compact ? .body : .headline)
                .labelStyle(.trailingIcon)
                .frame(minWidth: layout == .compact ? 0 : 60)
            }
            .buttonStyle(.bordered)
            .disabled(navigatorViewModel.isEmpty || navigatorViewModel.isAtLast)
            .accessibilityLabel("Last slice")
            .accessibilityHint("Jump to last slice in series")
        }
    }

    // MARK: - Slider View

    /// Slider for direct slice selection.
    ///
    /// Provides an interactive slider for jumping directly to any slice in the series.
    /// The slider range spans from 1 to the total number of slices, with single-slice
    /// stepping. Navigation occurs when the user releases the slider, not during dragging.
    private var sliderView: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Slice Navigation")
                .font(layout == .compact ? .caption2 : .caption)
                .foregroundColor(.secondary)

            HStack {
                Text("1")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .monospacedDigit()
                    .accessibilityHidden(true)

                Slider(
                    value: $tempSliderValue,
                    in: 0...Double(max(0, navigatorViewModel.totalCount - 1)),
                    step: 1.0,
                    onEditingChanged: { editing in
                        isEditingSlider = editing
                        if editing {
                            // User started dragging
                        } else {
                            // User finished dragging - apply navigation
                            navigatorViewModel.goToIndex(Int(tempSliderValue))
                        }
                    }
                )
                .accentColor(.accentColor)
                .accessibilityLabel("Slice navigation slider")
                .accessibilityValue("Slice \(Int(tempSliderValue) + 1) of \(navigatorViewModel.totalCount)")
                .accessibilityHint("Swipe up or down to navigate directly to any slice in the series")

                Text("\(navigatorViewModel.totalCount)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .monospacedDigit()
                    .accessibilityHidden(true)
            }
        }
    }

    // MARK: - Thumbnail Strip View

    /// Placeholder for thumbnail strip (future enhancement).
    ///
    /// Displays thumbnail placeholders for up to 10 slices in the series. Each thumbnail
    /// is a tappable placeholder that navigates to the corresponding slice when selected.
    /// The currently displayed slice is highlighted with accent color border.
    ///
    /// This is a placeholder implementation showing icon placeholders. In a future version,
    /// this could be enhanced to show actual image thumbnails using ``DicomImageRenderer``.
    private var thumbnailStripView: some View {
        VStack(spacing: 4) {
            Text("Thumbnails")
                .font(.caption2)
                .foregroundColor(.secondary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(0..<min(10, navigatorViewModel.totalCount), id: \.self) { index in
                        thumbnailPlaceholder(for: index)
                    }

                    if navigatorViewModel.totalCount > 10 {
                        Text("... +\(navigatorViewModel.totalCount - 10) more")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 8)
                    }
                }
            }
            .frame(height: 60)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Thumbnail strip")
        .accessibilityHint("Visual preview of series slices")
    }

    /// Creates a thumbnail placeholder.
    ///
    /// Generates a placeholder button for the specified slice index. Selected slices
    /// are highlighted with accent color border and background. All thumbnails show
    /// a photo icon as placeholder content with adaptive colors for dark mode.
    ///
    /// - Parameter index: The zero-based slice index
    /// Creates a tappable thumbnail placeholder for the slice at the given index.
    /// The thumbnail visually indicates the currently selected slice and navigates to the specified slice when activated.
    /// - Parameter index: Zero-based index of the slice.
    /// Creates a tappable thumbnail view for a specific slice index.
    /// - Parameter index: The zero-based index of the slice represented by this thumbnail.
    /// - Returns: A button-styled view that visually represents the slice at `index`, highlights when it matches the current slice, and navigates to that slice when activated. The view includes accessibility label, hint, and selection trait.
    private func thumbnailPlaceholder(for index: Int) -> some View {
        let isSelected = index == navigatorViewModel.currentIndex
        let fillColor = isSelected ? Color.accentColor.opacity(0.3) : Color.secondary.opacity(0.15)

        return Button(action: {
            navigatorViewModel.goToIndex(index)
        }) {
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
        .accessibilityLabel("Slice \(index + 1) thumbnail")
        .accessibilityHint("Double tap to navigate to slice \(index + 1)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

}

private extension View {
    @ViewBuilder
    func onChangeCompat<Value: Equatable>(
        of value: Value,
        fallback publisher: Published<Value>.Publisher,
        perform action: @escaping (Value) -> Void
    ) -> some View {
        if #available(iOS 14.0, macOS 11.0, *) {
            self.onChange(of: value, perform: action)
        } else {
            self.onReceive(publisher.removeDuplicates(), perform: action)
        }
    }
}

// MARK: - Custom Label Style

/// Label style that places the icon after the text.
///
/// A custom SwiftUI `LabelStyle` that reverses the default icon-text order,
/// placing the icon to the right of the text. Used for "Next" and "Last"
/// navigation buttons to maintain directional consistency.
///
/// ## Usage
///
/// ```swift
/// Label("Next", systemImage: "chevron.right")
///     .labelStyle(.trailingIcon)
/// ```
@available(iOS 14.0, macOS 12.0, *)
private struct TrailingIconLabelStyle: LabelStyle {
    /// Positions a label's title before its icon in a horizontal row with fixed spacing.
    /// - Parameter configuration: The label configuration containing `title` and `icon` views.
    /// Arranges a label's title followed by its icon in a horizontal layout.
    /// - Parameters:
    ///   - configuration: The label configuration providing `title` and `icon` views.
    /// - Returns: A view that places the title then the icon in an `HStack` with 6 points of spacing.
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) {
            configuration.title
            configuration.icon
        }
    }
}

@available(iOS 14.0, macOS 12.0, *)
extension LabelStyle where Self == TrailingIconLabelStyle {
    /// Creates a label style with icon placed after text.
    ///
    /// Convenience accessor for ``TrailingIconLabelStyle`` that allows dot-syntax usage.
    static var trailingIcon: TrailingIconLabelStyle {
        TrailingIconLabelStyle()
    }
}

// MARK: - SwiftUI Previews

#if DEBUG
@available(iOS 14.0, macOS 12.0, *)
struct SeriesNavigatorView_Previews: PreviewProvider {

    /// Creates sample series URLs for preview with realistic DICOM naming.
    /// - Parameters:
    ///   - count: Number of slices in the series
    ///   - modality: DICOM modality prefix (e.g., "CT", "MRI")
    ///   - studyName: Study description for file naming
    /// - Returns: Array of file URLs representing a DICOM series
    private static func createSampleSeriesURLs(count: Int, modality: String = "CT", studyName: String = "CHEST") -> [URL] {
        return (1...count).map { index in
            URL(fileURLWithPath: "/sample/series/\(modality)_\(studyName)_\(String(format: "%03d", index)).dcm")
        }
    }

    static var previews: some View {
        Group {
            // Expanded layout (default) with CT chest series
            SeriesNavigatorView(
                navigatorViewModel: {
                    let urls = createSampleSeriesURLs(count: 150, modality: "CT", studyName: "CHEST")
                    let vm = SeriesNavigatorViewModel(seriesURLs: urls)
                    vm.goToIndex(24) // Start at slice 25
                    return vm
                }()
            )
            .previewDisplayName("Expanded Layout - CT (25/150)")
            .frame(width: 500)
            .padding()

            // Compact layout with MRI series
            SeriesNavigatorView(
                navigatorViewModel: {
                    let urls = createSampleSeriesURLs(count: 50, modality: "MRI", studyName: "BRAIN")
                    let vm = SeriesNavigatorViewModel(seriesURLs: urls)
                    vm.goToIndex(9) // Start at slice 10
                    return vm
                }(),
                layout: .compact
            )
            .previewDisplayName("Compact Layout - MRI (10/50)")
            .frame(width: 400)
            .padding()

            // Empty state
            SeriesNavigatorView(
                navigatorViewModel: SeriesNavigatorViewModel()
            )
            .previewDisplayName("Empty State")
            .frame(width: 400)
            .padding()

            // First slice - CT series
            SeriesNavigatorView(
                navigatorViewModel: {
                    let urls = createSampleSeriesURLs(count: 100, modality: "CT", studyName: "ABDOMEN")
                    let vm = SeriesNavigatorViewModel(seriesURLs: urls)
                    return vm
                }()
            )
            .previewDisplayName("First Slice - CT (1/100)")
            .frame(width: 500)
            .padding()

            // Last slice - CT series
            SeriesNavigatorView(
                navigatorViewModel: {
                    let urls = createSampleSeriesURLs(count: 100, modality: "CT", studyName: "ABDOMEN")
                    let vm = SeriesNavigatorViewModel(seriesURLs: urls)
                    vm.goToLast()
                    return vm
                }()
            )
            .previewDisplayName("Last Slice - CT (100/100)")
            .frame(width: 500)
            .padding()

            // Dark mode with MRI series
            SeriesNavigatorView(
                navigatorViewModel: {
                    let urls = createSampleSeriesURLs(count: 75, modality: "MRI", studyName: "SPINE")
                    let vm = SeriesNavigatorViewModel(seriesURLs: urls)
                    vm.goToIndex(37)
                    return vm
                }()
            )
            .preferredColorScheme(.dark)
            .previewDisplayName("Dark Mode - MRI (38/75)")
            .frame(width: 500)
            .padding()

            // Light mode with MRI series
            SeriesNavigatorView(
                navigatorViewModel: {
                    let urls = createSampleSeriesURLs(count: 75, modality: "MRI", studyName: "SPINE")
                    let vm = SeriesNavigatorViewModel(seriesURLs: urls)
                    vm.goToIndex(37)
                    return vm
                }()
            )
            .preferredColorScheme(.light)
            .previewDisplayName("Light Mode - MRI (38/75)")
            .frame(width: 500)
            .padding()

            // Small series (10 images) - X-ray
            SeriesNavigatorView(
                navigatorViewModel: {
                    let urls = createSampleSeriesURLs(count: 10, modality: "XR", studyName: "CHEST")
                    let vm = SeriesNavigatorViewModel(seriesURLs: urls)
                    vm.goToIndex(4)
                    return vm
                }()
            )
            .previewDisplayName("Small Series - XR (5/10)")
            .frame(width: 500)
            .padding()
        }
    }
}
#endif
