//
//  DicomImageView.swift
//
//  SwiftUI view for displaying DICOM medical images
//
//  This view provides a complete DICOM image viewing experience with automatic
//  image loading, windowing transformations, loading indicators, and error
//  handling. It wraps DicomImageViewModel to provide reactive state management
//  and integrates seamlessly with SwiftUI's declarative view hierarchy.
//
//  The view automatically handles image scaling and aspect ratio preservation,
//  making it suitable for both embedded and full-screen display scenarios. It
//  supports both URL-based loading and pre-loaded DCMDecoder instances.
//
//  Platform Availability:
//
//  Available on iOS 13+, macOS 12+, and all platforms supporting SwiftUI.
//  Uses native SwiftUI components for optimal performance and platform integration.
//
//  Accessibility:
//
//  The view includes proper accessibility labels and hints for VoiceOver support.
//  Loading states and error messages are announced to assistive technologies.
//

import SwiftUI
import DicomCore

/// A SwiftUI view for displaying DICOM medical images.
///
/// ## Overview
///
/// ``DicomImageView`` provides a complete DICOM image viewing experience in SwiftUI.
/// It handles the entire image lifecycle: loading, windowing transformations, error
/// handling, and display. The view automatically adapts to different loading states
/// with progress indicators and error messages.
///
/// **Key Features:**
/// - Automatic image loading and rendering
/// - Loading state with progress indicator
/// - Error handling with descriptive messages
/// - Automatic aspect ratio preservation
/// - Resizable image with .fit content mode
/// - Accessibility support for VoiceOver
/// - Reactive updates via ``DicomImageViewModel``
///
/// **Display Characteristics:**
/// - Automatically scales to fit container
/// - Preserves original aspect ratio
/// - Uses grayscale color space for medical imaging
/// - Supports GPU-accelerated windowing
///
/// ## Usage
///
/// Load and display a DICOM file from URL:
///
/// ```swift
/// struct ContentView: View {
///     let dicomURL: URL
///
///     var body: some View {
///         DicomImageView(url: dicomURL)
///             .frame(width: 400, height: 400)
///             .border(Color.gray, width: 1)
///     }
/// }
/// ```
///
/// Display with custom windowing preset:
///
/// ```swift
/// DicomImageView(
///     url: dicomURL,
///     windowingMode: .preset(.lung)
/// )
/// .frame(maxWidth: .infinity, maxHeight: .infinity)
/// ```
///
/// Use pre-loaded decoder:
///
/// ```swift
/// Task {
///     do {
///         let decoder = try await DCMDecoder(contentsOfFile: url.path)
///
///         DicomImageView(decoder: decoder)
///             .aspectRatio(contentMode: .fit)
///     } catch {
///         // Handle DICOMError
///     }
/// }
/// ```
///
/// Access view model for custom interactions:
///
/// ```swift
/// struct CustomDicomViewer: View {
///     @StateObject private var viewModel = DicomImageViewModel()
///     let url: URL
///
///     var body: some View {
///         VStack {
///             DicomImageView(viewModel: viewModel)
///
///             // Custom controls
///             HStack {
///                 Button("Lung") {
///                     Task {
///                         await viewModel.updateWindowing(
///                             windowingMode: .preset(.lung)
///                         )
///                     }
///                 }
///                 Button("Bone") {
///                     Task {
///                         await viewModel.updateWindowing(
///                             windowingMode: .preset(.bone)
///                         )
///                     }
///                 }
///             }
///         }
///         .task {
///             await viewModel.loadImage(from: url)
///         }
///     }
/// }
/// ```
///
/// ## Topics
///
/// ### Creating a View
///
/// - ``init(url:windowingMode:processingMode:)``
/// - ``init(decoder:windowingMode:processingMode:)``
/// - ``init(viewModel:)``
///
/// ### View Modifiers
///
/// Apply standard SwiftUI modifiers for layout and styling:
/// - `.frame()` - Set container dimensions
/// - `.aspectRatio(contentMode:)` - Override default .fit mode
/// - `.background()` - Add background color
/// - `.border()` - Add border for debugging
///
@available(iOS 13.0, macOS 12.0, *)
public struct DicomImageView: View {

    // MARK: - Properties

    /// View model owned by this view (used by URL/decoder initializers).
    @StateObject private var ownedViewModel: DicomImageViewModel

    /// View model observed from outside this view (used by init(viewModel:)).
    @ObservedObject private var observedViewModel: DicomImageViewModel

    /// Indicates whether this instance is using an externally-managed observed model.
    private let usesObservedViewModel: Bool

    /// URL to load (if provided)
    private let url: URL?

    /// Decoder to load (if provided)
    private let decoder: DCMDecoder?

    /// Windowing mode to use
    private let windowingMode: DicomImageRenderer.WindowingMode

    /// Processing mode (CPU/GPU)
    private let processingMode: ProcessingMode

    /// Legacy task used for platforms that do not support `.task(id:)`.
    @State private var legacyLoadTask: Task<Void, Never>?

    /// Active view model for rendering and state access.
    private var viewModel: DicomImageViewModel {
        usesObservedViewModel ? observedViewModel : ownedViewModel
    }

    /// Stable key describing what should be auto-loaded by this view.
    private var loadTriggerKey: String {
        if let url {
            return "url:\(url.absoluteString)"
        }
        if let decoder {
            return "decoder:\(ObjectIdentifier(decoder).hashValue)"
        }
        return "none"
    }

    // MARK: - Initializers

    /// Creates a DICOM image view from a file URL.
    ///
    /// Loads and displays a DICOM image from the specified URL. The view automatically
    /// handles loading states, applies windowing transformations, and displays the
    /// resulting image with proper scaling.
    ///
    /// The view uses a ``DicomImageViewModel`` internally and triggers loading via
    /// SwiftUI's `.task()` modifier when the view appears.
    ///
    /// - Parameters:
    ///   - url: URL to the DICOM file (.dcm, .dicom)
    ///   - windowingMode: How to determine window/level values. Defaults to `.automatic`
    ///   - processingMode: CPU (vDSP) or GPU (Metal) acceleration. Defaults to `.auto`
    ///
    /// ## Example
    ///
    /// ```swift
    /// // Simple usage with automatic windowing
    /// DicomImageView(url: fileURL)
    ///
    /// // With CT lung preset
    /// DicomImageView(
    ///     url: ctURL,
    ///     windowingMode: .preset(.lung)
    /// )
    ///
    /// // Force GPU acceleration
    /// DicomImageView(
    ///     url: largeImageURL,
    ///     processingMode: .metal
    /// )
    /// ```
    ///
    public init(
        url: URL,
        windowingMode: DicomImageRenderer.WindowingMode = .automatic,
        processingMode: ProcessingMode = .auto
    ) {
        let viewModel = DicomImageViewModel()
        _ownedViewModel = StateObject(wrappedValue: viewModel)
        _observedViewModel = ObservedObject(wrappedValue: viewModel)
        self.usesObservedViewModel = false
        self.url = url
        self.decoder = nil
        self.windowingMode = windowingMode
        self.processingMode = processingMode
    }

    /// Creates a DICOM image view from a pre-loaded decoder.
    ///
    /// Displays a DICOM image from an existing ``DCMDecoder`` instance. This is useful
    /// when you already have a decoder (e.g., for metadata inspection) and want to
    /// display it with specific windowing settings.
    ///
    /// - Parameters:
    ///   - decoder: An initialized ``DCMDecoder`` with loaded DICOM file
    ///   - windowingMode: How to determine window/level values. Defaults to `.automatic`
    ///   - processingMode: CPU (vDSP) or GPU (Metal) acceleration. Defaults to `.auto`
    ///
    /// ## Example
    ///
    /// ```swift
    /// Task {
    ///     do {
    ///         // Load decoder first for metadata access
    ///         let decoder = try await DCMDecoder(contentsOfFile: url.path)
    ///         let patientName = decoder.info(for: .patientName)
    ///
    ///         // Display with preset
    ///         DicomImageView(
    ///             decoder: decoder,
    ///             windowingMode: .preset(.brain)
    ///         )
    ///     } catch {
    ///         // Handle DICOMError
    ///     }
    /// }
    /// ```
    ///
    public init(
        decoder: DCMDecoder,
        windowingMode: DicomImageRenderer.WindowingMode = .automatic,
        processingMode: ProcessingMode = .auto
    ) {
        let viewModel = DicomImageViewModel()
        _ownedViewModel = StateObject(wrappedValue: viewModel)
        _observedViewModel = ObservedObject(wrappedValue: viewModel)
        self.usesObservedViewModel = false
        self.url = nil
        self.decoder = decoder
        self.windowingMode = windowingMode
        self.processingMode = processingMode
    }

    /// Creates a DICOM image view with a custom view model.
    ///
    /// Allows you to provide your own ``DicomImageViewModel`` instance for advanced
    /// scenarios where you need to control loading or share state between views. You
    /// are responsible for calling ``DicomImageViewModel/loadImage(from:windowingMode:processingMode:)``
    /// on the view model. The view *observes* this external model and does not own it.
    ///
    /// - Parameter viewModel: A ``DicomImageViewModel`` instance to manage state
    ///
    /// ## Example
    ///
    /// ```swift
    /// struct CustomViewer: View {
    ///     @StateObject private var viewModel = DicomImageViewModel()
    ///
    ///     var body: some View {
    ///         VStack {
    ///             DicomImageView(viewModel: viewModel)
    ///
    ///             Button("Reload") {
    ///                 Task {
    ///                     await viewModel.loadImage(from: url)
    ///                 }
    ///             }
    ///         }
    ///         .task {
    ///             await viewModel.loadImage(from: url)
    ///         }
    ///     }
    /// }
    /// ```
    ///
    public init(viewModel: DicomImageViewModel) {
        _ownedViewModel = StateObject(wrappedValue: DicomImageViewModel())
        _observedViewModel = ObservedObject(wrappedValue: viewModel)
        self.usesObservedViewModel = true
        self.url = nil
        self.decoder = nil
        self.windowingMode = .automatic
        self.processingMode = .auto
    }

    // MARK: - Body

    public var body: some View {
        autoLoadCompatibleContent
            .accessibilityElement(children: .contain)
            .accessibilityLabel("DICOM Image Viewer")
    }

    @ViewBuilder
    private var autoLoadCompatibleContent: some View {
        if #available(iOS 15.0, *) {
            baseContent
                .task(id: loadTriggerKey) {
                    await performAutoLoad()
                }
                .onDisappear {
                    cancelLegacyLoadTask()
                }
        } else if #available(iOS 14.0, *) {
            baseContent
                .onAppear {
                    startLegacyLoadTask()
                }
                .onDisappear {
                    cancelLegacyLoadTask()
                }
                .onChange(of: loadTriggerKey) { _ in
                    startLegacyLoadTask()
                }
        } else {
            baseContent
                .onAppear {
                    startLegacyLoadTask()
                }
                .onDisappear {
                    cancelLegacyLoadTask()
                }
        }
    }

    private var baseContent: some View {
        ZStack {
            // Black background for medical imaging (standard for both light and dark mode)
            Color.black
                .modifier(FullScreenBackgroundModifier())
                .accessibilityHidden(true)

            switch viewModel.state {
            case .idle:
                idleStateView

            case .loading:
                loadingStateView

            case .loaded:
                loadedStateView

            case .failed(let error):
                errorStateView(error)
            }
        }
    }

    // MARK: - State Views

    /// View displayed when idle (no image loaded).
    ///
    /// Shows a placeholder icon and message indicating the view is ready to load a
    /// DICOM image. This state is displayed before any loading has been initiated.
    private var idleStateView: some View {
        VStack(spacing: 12) {
            Image(systemName: "photo.on.rectangle")
                .font(.system(size: 48))
                .foregroundColor(.secondary)

            Text("Ready to load DICOM image")
                .font(.callout)
                .foregroundColor(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("No image loaded")
        .accessibilityHint("Waiting for DICOM file to load")
    }

    /// View displayed while loading.
    ///
    /// Shows an animated progress indicator with loading message. Displayed while the
    /// DICOM file is being decoded and the windowing transformation is being applied.
    private var loadingStateView: some View {
        VStack(spacing: 16) {
            if #available(iOS 14.0, macOS 11.0, *) {
                ProgressView()
                    .scaleEffect(1.5)
                    .progressViewStyle(CircularProgressViewStyle())
            } else {
                Image(systemName: "hourglass")
                    .font(.system(size: 36))
                    .foregroundColor(.secondary)
            }

            Text("Loading DICOM image...")
                .font(.callout)
                .foregroundColor(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Loading")
        .accessibilityHint("DICOM image is being loaded")
    }

    /// View displayed when image loaded successfully.
    ///
    /// Shows the rendered DICOM image scaled to fit the container while preserving
    /// aspect ratio. Includes accessibility labels with image dimensions.
    private var loadedStateView: some View {
        Group {
            if let cgImage = viewModel.image {
                Image(decorative: cgImage, scale: 1.0)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .accessibilityLabel("DICOM medical image")
                    .accessibilityHint("Medical image, dimensions \(viewModel.imageWidth) by \(viewModel.imageHeight) pixels")
                    .accessibilityAddTraits(.isImage)
            } else {
                Text("Image loaded but not available")
                    .foregroundColor(.secondary)
                    .accessibilityLabel("Error")
                    .accessibilityHint("Image loaded but display failed")
            }
        }
    }

    /// View displayed when loading fails.
    ///
    /// Shows an error icon with descriptive error message. Provides details about
    /// why the DICOM file failed to load (file not found, invalid format, etc.).
    ///
    /// - Parameter error: The error that occurred during loading
    /// Builds the error state UI shown when loading a DICOM image fails.
    /// - Parameter error: The `DICOMError` describing the failure; its `localizedDescription` is displayed to the user.
    /// Displays an error UI for a failed DICOM image load.
    ///
    /// Shows a warning icon, a bold "Failed to Load Image" headline, and the error's localized description. The view is an accessibility element with label "Error loading image" and a hint set to the error's localized description.
    /// - Parameter error: The `DICOMError` describing the failure; its `localizedDescription` is displayed as the message.
    /// - Returns: A view presenting the error state for the DICOM image viewer.
    private func errorStateView(_ error: DICOMError) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundColor(.red)

            VStack(spacing: 8) {
                Text("Failed to Load Image")
                    .font(.headline)
                    .foregroundColor(.primary)

                Text(error.localizedDescription)
                    .font(.callout)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Error loading image")
        .accessibilityHint(error.localizedDescription)
    }

    private func startLegacyLoadTask() {
        cancelLegacyLoadTask()
        legacyLoadTask = Task {
            await performAutoLoad()
        }
    }

    private func cancelLegacyLoadTask() {
        legacyLoadTask?.cancel()
        legacyLoadTask = nil
    }

    private func performAutoLoad() async {
        // Auto-load if URL provided
        if let url = url {
            await viewModel.loadImage(
                from: url,
                windowingMode: windowingMode,
                processingMode: processingMode
            )
        } else if let decoder = decoder {
            await viewModel.loadImage(
                decoder: decoder,
                windowingMode: windowingMode,
                processingMode: processingMode
            )
        }
    }
}

private struct FullScreenBackgroundModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 14.0, macOS 11.0, *) {
            content.ignoresSafeArea()
        } else {
            content.edgesIgnoringSafeArea(.all)
        }
    }
}

// MARK: - SwiftUI Previews

#if DEBUG
@available(iOS 13.0, macOS 12.0, *)
struct DicomImageView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            // CT with different windowing presets
            DicomImageView(viewModel: DicomImageViewModel.preview(.ctLung))
                .previewDisplayName("CT - Lung Window")
                .previewSize(.medium)

            DicomImageView(viewModel: DicomImageViewModel.preview(.ctBone))
                .previewDisplayName("CT - Bone Window")
                .previewSize(.medium)

            DicomImageView(viewModel: DicomImageViewModel.preview(.ctBrain))
                .previewDisplayName("CT - Brain Window")
                .previewSize(.medium)

            DicomImageView(viewModel: DicomImageViewModel.preview(.ctAbdomen))
                .previewDisplayName("CT - Abdomen Soft Tissue")
                .previewSize(.medium)

            // MRI examples
            DicomImageView(viewModel: DicomImageViewModel.preview(.mrBrain))
                .previewDisplayName("MRI - Brain T1")
                .previewSize(.medium)

            DicomImageView(viewModel: DicomImageViewModel.preview(.mrSpine))
                .previewDisplayName("MRI - Spine T2")
                .previewSize(.medium)

            // X-Ray example
            DicomImageView(viewModel: DicomImageViewModel.preview(.xrayChest))
                .previewDisplayName("X-Ray - Chest PA")
                .previewSize(.medium)

            // Ultrasound example
            DicomImageView(viewModel: DicomImageViewModel.preview(.ultrasound))
                .previewDisplayName("Ultrasound - Abdomen")
                .previewSize(.medium)

            // Different sizes
            DicomImageView(viewModel: DicomImageViewModel.preview(.ctLung))
                .previewDisplayName("Small Size")
                .previewSize(.small)

            DicomImageView(viewModel: DicomImageViewModel.preview(.ctLung))
                .previewDisplayName("Large Size")
                .previewSize(.large)

            // Dark/Light mode comparison
            DicomImageView(viewModel: DicomImageViewModel.preview(.ctBrain))
                .preferredColorScheme(.dark)
                .previewDisplayName("CT Brain - Dark Mode")
                .previewSize(.medium)

            DicomImageView(viewModel: DicomImageViewModel.preview(.ctBrain))
                .preferredColorScheme(.light)
                .previewDisplayName("CT Brain - Light Mode")
                .previewSize(.medium)

            // State examples
            DicomImageView(viewModel: DicomImageViewModel())
                .previewDisplayName("Idle State")
                .previewSize(.medium)

            DicomImageView(viewModel: PreviewHelpers.loadingViewModel())
                .previewDisplayName("Loading State")
                .previewSize(.medium)
        }
    }
}
#endif
