//
//  DicomImageViewModel.swift
//
//  ViewModel for managing DICOM image display state
//
//  This view model handles the complete lifecycle of DICOM image rendering:
//  file loading, windowing transformations, error handling, and state management.
//  It coordinates DCMDecoder and DicomImageRenderer to provide a SwiftUI-friendly
//  API with reactive state updates via @Published properties.
//
//  The view model supports both synchronous and asynchronous loading, automatic
//  and manual windowing, medical imaging presets, and GPU acceleration. Error
//  handling is integrated throughout with detailed diagnostics.
//
//  Thread Safety:
//
//  All methods marked with @MainActor run on the main thread, ensuring UI updates
//  are safe. The ViewModel uses structured concurrency for background operations.
//  @Published properties automatically update the UI when changed.
//
//  Performance Characteristics:
//
//  Image loading and rendering typically takes 10-70ms depending on file size
//  and image dimensions. The view model performs heavy operations on background
//  threads and publishes results to the main actor for UI updates.
//

import Foundation
import SwiftUI
import Combine
import OSLog
import DicomCore

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

// MARK: - Loading State

/// Loading state for DICOM image operations.
///
/// Represents the current state of image loading and rendering operations.
/// Used by ``DicomImageViewModel`` to track progress and communicate status to views.
///
public enum DicomImageLoadingState: Equatable {
    /// No operation in progress
    case idle

    /// Loading DICOM file and rendering image
    case loading

    /// Image successfully loaded and rendered
    case loaded

    /// Error occurred during loading or rendering
    case failed(DICOMError)

    /// Determines whether two `DicomImageLoadingState` values are equal.
    /// 
    /// Equality is true when both values are the same case. If both are `.failed`, their associated `DICOMError` values are compared for equality.
    /// - Parameters:
    ///   - lhs: The left-hand `DicomImageLoadingState`.
    ///   - rhs: The right-hand `DicomImageLoadingState`.
    /// Compare two `DicomImageLoadingState` values for equality.
    /// When both states are `.failed`, the associated `DICOMError` values are compared for equality.
    /// - Returns: `true` if both states are the same case (and for `.failed`, their associated errors are equal), `false` otherwise.

    public static func == (lhs: DicomImageLoadingState, rhs: DicomImageLoadingState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle), (.loading, .loading), (.loaded, .loaded):
            return true
        case (.failed(let lhsError), .failed(let rhsError)):
            return lhsError == rhsError
        default:
            return false
        }
    }
}

// MARK: - View Model

/// View model for managing DICOM image display state.
///
/// ## Overview
///
/// ``DicomImageViewModel`` provides reactive state management for DICOM image viewing
/// in SwiftUI applications. It handles the complete image pipeline: file loading,
/// windowing transformations, error handling, and state updates. The view model uses
/// ``DicomImageRenderer`` internally for all rendering operations.
///
/// **Key Features:**
/// - Reactive state with `@Published` properties
/// - Async/await support for non-blocking operations
/// - Automatic and manual windowing modes
/// - 13 medical imaging presets (lung, bone, brain, etc.)
/// - GPU acceleration support
/// - Comprehensive error handling with recovery suggestions
/// - Thread-safe operations with main actor isolation
///
/// ## Usage
///
/// Basic usage with automatic windowing:
///
/// ```swift
/// struct DicomImageView: View {
///     @StateObject private var viewModel = DicomImageViewModel()
///     let fileURL: URL
///
///     var body: some View {
///         VStack {
///             switch viewModel.state {
///             case .idle:
///                 Text("Ready to load")
///             case .loading:
///                 ProgressView("Loading...")
///             case .loaded:
///                 if let image = viewModel.image {
///                     Image(decorative: image, scale: 1.0)
///                         .resizable()
///                         .aspectRatio(contentMode: .fit)
///                 }
///             case .failed(let error):
///                 Text("Error: \(error.localizedDescription)")
///             }
///         }
///         .task {
///             await viewModel.loadImage(from: fileURL)
///         }
///     }
/// }
/// ```
///
/// Load with custom windowing:
///
/// ```swift
/// @StateObject private var viewModel = DicomImageViewModel()
///
/// // Load with specific window/level
/// await viewModel.loadImage(
///     from: url,
///     windowingMode: .custom(center: 50, width: 400)
/// )
///
/// // Load with medical preset
/// await viewModel.loadImage(
///     from: url,
///     windowingMode: .preset(.lung),
///     processingMode: .metal  // Force GPU acceleration
/// )
/// ```
///
/// Update windowing after loading:
///
/// ```swift
/// // Load image first
/// await viewModel.loadImage(from: url)
///
/// // Re-render with different windowing
/// await viewModel.updateWindowing(
///     windowingMode: .preset(.bone)
/// )
/// ```
///
/// ## Topics
///
/// ### Creating a View Model
///
/// - ``init()``
///
/// ### Loading Images
///
/// - ``loadImage(from:windowingMode:processingMode:)``
/// - ``loadImage(decoder:windowingMode:processingMode:)``
///
/// ### Updating Display
///
/// - ``updateWindowing(windowingMode:processingMode:)``
/// - ``reset()``
///
/// ### State Properties
///
/// - ``state``
/// - ``image``
/// - ``currentWindowSettings``
/// - ``decoder``
/// - ``error``
///
@MainActor
public final class DicomImageViewModel: ObservableObject {

    // MARK: - Published Properties

    /// Current loading state
    @Published public private(set) var state: DicomImageLoadingState = .idle

    /// Currently displayed CGImage (nil when not loaded)
    @Published public private(set) var image: CGImage?

    /// Current window settings used for rendering (nil when not loaded)
    @Published public private(set) var currentWindowSettings: WindowSettings?

    /// Current DICOM decoder (nil when not loaded, useful for metadata access)
    @Published public private(set) var decoder: DCMDecoder?

    /// Most recent error (nil when no error)
    @Published public private(set) var error: DICOMError?

    // MARK: - Private Properties

    private let logger: Logger
    private var renderDecoder: (any DicomImageRendererDecoderProtocol)?
    private var loadGeneration: UInt64 = 0

    // MARK: - Initialization

    /// Creates a new DICOM image view model.
    ///
    /// Initializes the view model with idle state and sets up logging infrastructure.
    /// The view model is ready to load images via ``loadImage(from:windowingMode:processingMode:)``
    /// or ``loadImage(decoder:windowingMode:processingMode:)``.
    ///
    /// ## Example
    ///
    /// ```swift
    /// struct MyView: View {
    ///     @StateObject private var viewModel = DicomImageViewModel()
    ///
    ///     var body: some View {
    ///         // Use viewModel here
    ///     }
    /// }
    /// ```
    ///
    public init() {
        self.logger = Logger(subsystem: "com.dicomswiftui", category: "DicomImageViewModel")
        logger.info("📊 DicomImageViewModel initialized")
    }

    // MARK: - Public Interface

    /// Loads and renders a DICOM image from URL.
    ///
    /// Asynchronously loads the DICOM file, applies windowing transformation, and updates
    /// the ``image`` property with the rendered result. The ``state`` property tracks
    /// progress through the loading pipeline.
    ///
    /// The method performs heavy operations on background threads and publishes results
    /// to the main actor for UI updates. If an error occurs, the ``state`` transitions
    /// to `.failed` and the ``error`` property is populated.
    ///
    /// - Parameters:
    ///   - url: URL to the DICOM file (.dcm, .dicom)
    ///   - windowingMode: How to determine window/level values. Defaults to `.automatic`
    ///   - processingMode: CPU (vDSP) or GPU (Metal) acceleration. Defaults to `.auto`
    ///
    /// ## Example
    ///
    /// ```swift
    /// @StateObject private var viewModel = DicomImageViewModel()
    ///
    /// // In view body or task:
    /// await viewModel.loadImage(from: fileURL)
    ///
    /// // With custom settings:
    /// await viewModel.loadImage(
    ///     from: fileURL,
    ///     windowingMode: .preset(.lung),
    ///     processingMode: .metal
    /// )
    /// ```
    /// Loads a DICOM file from the given URL, renders an image using the specified windowing and processing modes, and updates the view model's published state.
    /// - Parameters:
    ///   - from: The file URL of the DICOM dataset to load.
    ///   - windowingMode: The windowing mode to apply when rendering the image; determines how window/level values are selected.
    ///   - processingMode: The image processing mode to use during rendering; controls algorithms or quality/performance trade-offs.
    /// Load and render a DICOM image from the given file URL and update the view model's published state.
    ///
    /// Updates the view model's `image`, `decoder`, `currentWindowSettings`, `state`, and `error` to reflect the outcome; on failure the `state` will be set to `.failed` and `error` populated with the encountered `DICOMError`.
    /// - Parameters:
    ///   - url: File URL of the DICOM file to load.
    ///   - windowingMode: Windowing mode to use when rendering the image. Defaults to `.automatic`.
    ///   - processingMode: Pixel processing mode to use during rendering. Defaults to `.auto`.
    public func loadImage(
        from url: URL,
        windowingMode: DicomImageRenderer.WindowingMode = .automatic,
        processingMode: ProcessingMode = .auto
    ) async {
        let generation = beginNewLoadGeneration()
        logger.info("🔍 Loading DICOM image from: \(url.lastPathComponent)")

        // Reset state
        state = .loading
        image = nil
        error = nil
        currentWindowSettings = nil
        decoder = nil
        renderDecoder = nil

        do {
            // Load decoder first (for metadata access)
            let loadedDecoder = try await DCMDecoder(contentsOf: url)
            guard ensureCurrentGeneration(generation, operation: "image load") else {
                return
            }

            decoder = loadedDecoder
            renderDecoder = loadedDecoder

            logger.debug("✅ Decoder loaded: \(loadedDecoder.width)×\(loadedDecoder.height)")

            // Render image
            let renderedImage = try await DicomImageRenderer.renderAsync(
                decoder: loadedDecoder,
                windowingMode: windowingMode,
                processingMode: processingMode
            )
            guard ensureCurrentGeneration(generation, operation: "image load") else {
                return
            }

            // Resolve actual window settings used
            let settings = try resolveWindowSettings(
                mode: windowingMode,
                decoder: loadedDecoder
            )
            guard ensureCurrentGeneration(generation, operation: "image load") else {
                return
            }

            // Update state on main actor
            image = renderedImage
            currentWindowSettings = settings
            state = .loaded

            logger.info("✅ Image loaded successfully: \(renderedImage.width)×\(renderedImage.height)")

        } catch let dicomError as DICOMError {
            guard ensureCurrentGeneration(generation, operation: "image load failure") else {
                return
            }
            logger.error("❌ Failed to load image: \(dicomError.localizedDescription)")
            error = dicomError
            state = .failed(dicomError)

        } catch {
            guard ensureCurrentGeneration(generation, operation: "image load failure") else {
                return
            }
            logger.error("❌ Unexpected error: \(error.localizedDescription)")
            let dicomError = DICOMError.unknown(underlyingError: error.localizedDescription)
            self.error = dicomError
            state = .failed(dicomError)
        }
    }

    /// Loads and renders a DICOM image from an existing decoder.
    ///
    /// Renders an image from a pre-loaded ``DCMDecoder`` instance. This is useful when you
    /// already have a decoder (e.g., for metadata inspection) and want to render it with
    /// specific windowing settings.
    ///
    /// - Parameters:
    ///   - decoder: An initialized ``DCMDecoder`` with loaded DICOM file
    ///   - windowingMode: How to determine window/level values. Defaults to `.automatic`
    ///   - processingMode: CPU (vDSP) or GPU (Metal) acceleration. Defaults to `.auto`
    ///
    /// ## Example
    ///
    /// ```swift
    /// let decoder = try DCMDecoder(contentsOf: url)
    /// let patientName = decoder.info(for: .patientName)
    ///
    /// @StateObject private var viewModel = DicomImageViewModel()
    /// await viewModel.loadImage(decoder: decoder)
    /// ```
    /// Load and render a DICOM image from an existing decoder and update the view model's published state.
    /// 
    /// Stores the provided decoder, renders an image using the requested windowing and processing modes,
    /// resolves the actual window settings used, and updates `image`, `currentWindowSettings`, `state`, and `error`.
    /// - Parameters:
    ///   - inputDecoder: The `DCMDecoder` instance providing pixel data and metadata; it will be stored on the view model and used for rendering.
    ///   - windowingMode: The requested windowing mode to apply when rendering; may be automatic, preset, custom, or taken from the decoder.
    /// Load and render a DICOM image from an existing `DCMDecoder` and update the view model's published state and image.
    /// 
    /// On success the view model's `image`, `currentWindowSettings`, and `state` are updated to the loaded image and `.loaded`.
    /// On failure the view model's `error` and `state` are set to the encountered `DICOMError`.
    /// - Parameters:
    ///   - decoder: The `DCMDecoder` containing the DICOM pixel data and metadata to render.
    ///   - windowingMode: The windowing selection to use for rendering (e.g., automatic, preset, custom, or from-decoder).
    ///   - processingMode: The image processing mode to use for rendering.
    public func loadImage(
        decoder inputDecoder: DCMDecoder,
        windowingMode: DicomImageRenderer.WindowingMode = .automatic,
        processingMode: ProcessingMode = .auto
    ) async {
        let generation = beginNewLoadGeneration()
        await loadImage(
            decoder: inputDecoder as any DicomImageRendererDecoderProtocol,
            windowingMode: windowingMode,
            processingMode: processingMode,
            generation: generation
        )
    }

    /// Load and render a DICOM image from a protocol-based decoder and update the view model's published state and image.
    ///
    /// This overload is intended for dependency injection (for example unit tests), allowing callers
    /// to provide a lightweight decoder conforming to ``DicomImageRendererDecoderProtocol``.
    /// - Parameters:
    ///   - inputDecoder: Any decoder implementation that provides width/height, pixels, and window metadata.
    ///   - windowingMode: The windowing selection to use for rendering (e.g., automatic, preset, custom, or from-decoder).
    ///   - processingMode: The image processing mode to use for rendering.
    public func loadImage(
        decoder inputDecoder: any DicomImageRendererDecoderProtocol,
        windowingMode: DicomImageRenderer.WindowingMode = .automatic,
        processingMode: ProcessingMode = .auto
    ) async {
        let generation = beginNewLoadGeneration()
        await loadImage(
            decoder: inputDecoder,
            windowingMode: windowingMode,
            processingMode: processingMode,
            generation: generation
        )
    }

    private func loadImage(
        decoder inputDecoder: any DicomImageRendererDecoderProtocol,
        windowingMode: DicomImageRenderer.WindowingMode,
        processingMode: ProcessingMode,
        generation: UInt64
    ) async {
        logger.info("🔍 Loading DICOM image from decoder: \(inputDecoder.width)×\(inputDecoder.height)")

        // Reset state
        state = .loading
        image = nil
        error = nil
        currentWindowSettings = nil
        decoder = inputDecoder as? DCMDecoder
        renderDecoder = inputDecoder

        do {
            // Render image
            let renderedImage = try await DicomImageRenderer.renderAsync(
                decoder: inputDecoder,
                windowingMode: windowingMode,
                processingMode: processingMode
            )
            guard ensureCurrentGeneration(generation, operation: "image load") else {
                return
            }

            // Resolve actual window settings used
            let settings = try resolveWindowSettings(
                mode: windowingMode,
                decoder: inputDecoder
            )
            guard ensureCurrentGeneration(generation, operation: "image load") else {
                return
            }

            // Update state on main actor
            image = renderedImage
            currentWindowSettings = settings
            state = .loaded

            logger.info("✅ Image loaded successfully: \(renderedImage.width)×\(renderedImage.height)")

        } catch let dicomError as DICOMError {
            guard ensureCurrentGeneration(generation, operation: "image load failure") else {
                return
            }
            logger.error("❌ Failed to load image: \(dicomError.localizedDescription)")
            error = dicomError
            state = .failed(dicomError)

        } catch {
            guard ensureCurrentGeneration(generation, operation: "image load failure") else {
                return
            }
            logger.error("❌ Unexpected error: \(error.localizedDescription)")
            let dicomError = DICOMError.unknown(underlyingError: error.localizedDescription)
            self.error = dicomError
            state = .failed(dicomError)
        }
    }

    /// Updates the displayed image with new windowing settings.
    ///
    /// Re-renders the current image with different window/level values without reloading
    /// the DICOM file. This is more efficient than calling ``loadImage(from:windowingMode:processingMode:)``
    /// again when only windowing parameters need to change.
    ///
    /// **Precondition:** A decoder must already be loaded (``decoder`` must not be nil).
    /// Call ``loadImage(from:windowingMode:processingMode:)`` or ``loadImage(decoder:windowingMode:processingMode:)``
    /// first.
    ///
    /// - Parameters:
    ///   - windowingMode: New windowing mode to apply
    ///   - processingMode: CPU (vDSP) or GPU (Metal) acceleration. Defaults to `.auto`
    ///
    /// ## Example
    ///
    /// ```swift
    /// // Load image first
    /// await viewModel.loadImage(from: url)
    ///
    /// // User changes preset - re-render without reloading file
    /// await viewModel.updateWindowing(windowingMode: .preset(.bone))
    ///
    /// // User adjusts custom values
    /// await viewModel.updateWindowing(
    ///     windowingMode: .custom(center: centerSlider.value, width: widthSlider.value)
    /// )
    /// ```
    /// Re-renders the currently loaded DICOM image using the specified windowing and processing modes and updates the view model's published state.
    /// 
    /// If no decoder is loaded the method records a `DICOMError.invalidPixelData` and sets the state to `.failed`.
    /// On success the method updates `image`, `currentWindowSettings`, and sets the state to `.loaded`. On failure it records the error and sets the state to `.failed`.
    /// - Parameters:
    ///   - windowingMode: The windowing source to apply (automatic, preset, custom, or from-decoder).
    /// Re-renders the currently loaded DICOM image using the specified windowing and processing modes.
    /// 
    /// If no decoder is loaded, the view model's `error` is set to `DICOMError.invalidPixelData` and `state` is set to `.failed`.
    /// - Parameters:
    ///   - windowingMode: The window/level selection mode to apply for rendering.
    ///   - processingMode: The image processing mode to use for rendering (defaults to `.auto`).
    public func updateWindowing(
        windowingMode: DicomImageRenderer.WindowingMode,
        processingMode: ProcessingMode = .auto
    ) async {
        let generation = beginNewLoadGeneration()
        guard let renderDecoder else {
            logger.warning("⚠️ Cannot update windowing: no decoder loaded")
            let error = DICOMError.invalidPixelData(reason: "No DICOM file loaded")
            self.error = error
            state = .failed(error)
            return
        }

        logger.info("🔄 Updating windowing")

        // Set loading state
        state = .loading
        error = nil

        do {
            // Render image with new windowing
            let renderedImage = try await DicomImageRenderer.renderAsync(
                decoder: renderDecoder,
                windowingMode: windowingMode,
                processingMode: processingMode
            )
            guard ensureCurrentGeneration(generation, operation: "windowing update") else {
                return
            }

            // Resolve actual window settings used
            let settings = try resolveWindowSettings(
                mode: windowingMode,
                decoder: renderDecoder
            )
            guard ensureCurrentGeneration(generation, operation: "windowing update") else {
                return
            }

            // Update state on main actor
            image = renderedImage
            currentWindowSettings = settings
            state = .loaded

            logger.info("✅ Windowing updated successfully")

        } catch let dicomError as DICOMError {
            guard ensureCurrentGeneration(generation, operation: "windowing update failure") else {
                return
            }
            logger.error("❌ Failed to update windowing: \(dicomError.localizedDescription)")
            error = dicomError
            state = .failed(dicomError)

        } catch {
            guard ensureCurrentGeneration(generation, operation: "windowing update failure") else {
                return
            }
            logger.error("❌ Unexpected error: \(error.localizedDescription)")
            let dicomError = DICOMError.unknown(underlyingError: error.localizedDescription)
            self.error = dicomError
            state = .failed(dicomError)
        }
    }

    /// Resets the view model to idle state.
    ///
    /// Clears all state including image, decoder, error, and window settings. Use this
    /// when unloading an image or preparing to load a new one.
    ///
    /// ## Example
    ///
    /// ```swift
    /// // User closes image viewer
    /// viewModel.reset()
    ///
    /// // Load new image
    /// await viewModel.loadImage(from: newURL)
    /// ```
    /// Resets the view model to its initial idle state.
    /// 
    /// Reset the view model to its initial idle state.
    /// Clears the loaded image, decoder, current window settings, and any recorded error, and sets `state` to `idle`.
    public func reset() {
        logger.debug("🔄 Resetting view model")
        _ = beginNewLoadGeneration()

        state = .idle
        image = nil
        decoder = nil
        renderDecoder = nil
        error = nil
        currentWindowSettings = nil
    }

    // MARK: - Private Helpers

    /// Resolves window settings based on the windowing mode.
    ///
    /// Determines the actual window center and width values that were used for rendering,
    /// based on the specified windowing mode. This allows the view model to expose the
    /// exact settings used for display.
    ///
    /// - Parameters:
    ///   - mode: The windowing mode to resolve
    ///   - decoder: The DICOM decoder (used for `.fromDecoder` mode)
    ///
    /// - Returns: The resolved window settings
    ///
    /// - Throws: ``DICOMError/invalidPixelData(reason:)`` if automatic calculation fails
    /// Resolve the concrete window and level settings to use for rendering based on the requested windowing mode.
    /// - Parameters:
    ///   - mode: The requested windowing mode which may be `.automatic`, `.preset`, `.custom`, or `.fromDecoder`.
    ///   - decoder: The `DCMDecoder` used to read embedded window settings or pixel data required for calculations.
    /// - Returns: The resolved `WindowSettings` appropriate for the chosen mode.
    /// Resolve concrete window/level settings for the specified windowing mode using the provided decoder.
    /// - Parameters:
    ///   - mode: The windowing mode to resolve (automatic, preset, custom, or fromDecoder).
    ///   - decoder: The DICOM decoder supplying pixel data and any stored window settings.
    /// - Returns: The resolved `WindowSettings` (center and width) to use for rendering.
    /// - Throws: `DICOMError.invalidPixelData` when pixel data required for automatic calculation or fallback is missing.
    private func resolveWindowSettings(
        mode: DicomImageRenderer.WindowingMode,
        decoder: any DicomImageRendererDecoderProtocol
    ) throws -> WindowSettings {
        switch mode {
        case .automatic:
            // Get pixels for histogram calculation
            guard let pixels16 = decoder.getPixels16() else {
                throw DICOMError.invalidPixelData(reason: "Missing pixel data for automatic windowing")
            }
            return DCMWindowingProcessor.calculateOptimalWindowLevelV2(pixels16: pixels16)

        case .preset(let medicalPreset):
            return DCMWindowingProcessor.getPresetValuesV2(preset: medicalPreset)

        case .custom(let center, let width):
            return WindowSettings(center: center, width: width)

        case .fromDecoder:
            let settings = decoder.windowSettingsV2
            if settings.isValid {
                return settings
            } else {
                // Fallback to automatic if metadata invalid
                guard let pixels16 = decoder.getPixels16() else {
                    throw DICOMError.invalidPixelData(reason: "Missing pixel data for automatic windowing fallback")
                }
                return DCMWindowingProcessor.calculateOptimalWindowLevelV2(pixels16: pixels16)
            }
        }
    }

    private func beginNewLoadGeneration() -> UInt64 {
        loadGeneration &+= 1
        return loadGeneration
    }

    private func ensureCurrentGeneration(_ generation: UInt64, operation: String) -> Bool {
        guard generation == loadGeneration else {
            logger.debug("🔄 Discarding stale \(operation) result")
            return false
        }
        return true
    }
}

// MARK: - Convenience Computed Properties

extension DicomImageViewModel {

    /// Returns true if an image is currently loaded
    public var isLoaded: Bool {
        if case .loaded = state {
            return true
        }
        return false
    }

    /// Returns true if an operation is in progress
    public var isLoading: Bool {
        if case .loading = state {
            return true
        }
        return false
    }

    /// Returns true if the view model has failed
    public var hasFailed: Bool {
        if case .failed = state {
            return true
        }
        return false
    }

    /// Returns the image width if loaded, otherwise 0
    public var imageWidth: Int {
        return image?.width ?? 0
    }

    /// Returns the image height if loaded, otherwise 0
    public var imageHeight: Int {
        return image?.height ?? 0
    }
}
