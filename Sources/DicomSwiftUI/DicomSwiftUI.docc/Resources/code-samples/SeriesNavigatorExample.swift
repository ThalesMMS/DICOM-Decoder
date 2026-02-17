import SwiftUI
import DicomSwiftUI
import DicomCore
#if os(iOS) || os(tvOS) || os(visionOS)
import UIKit
#endif
#if os(macOS)
import AppKit
#endif

private var platformSystemBackground: Color {
#if os(iOS) || os(tvOS) || os(visionOS)
    return Color(UIColor.systemBackground)
#elseif os(macOS)
    return Color(NSColor.windowBackgroundColor)
#else
    return Color.secondary
#endif
}

// MARK: - Basic Series Navigation

/// Provides a simple SwiftUI example that displays a DICOM series with navigation controls.
/// 
/// Note: Requires iOS 13+ and macOS 12+ and relies on SwiftUI concurrency/async-await, so older OS versions are not supported.
/// The view shows the current DICOM image and a series navigator. When the view appears it loads the first slice, and selecting a different slice via the navigator loads that slice into the image view.
/// Creates a SwiftUI example view that displays a DICOM image and a series navigator which loads selected slices.
///
/// The returned view initializes a navigator and image view model, sets the navigator with a 100-slice placeholder series on appear, loads the first slice, and updates the displayed image when the user navigates.
/// - Returns: A view containing a `DicomImageView` and a `SeriesNavigatorView` that loads images from the selected series URLs when navigation occurs.
func basicSeriesNavigation() -> some View {
    struct BasicSeriesView: View {
        @StateObject private var navigatorVM = SeriesNavigatorViewModel()
        @StateObject private var imageVM = DicomImageViewModel()
        let seriesURLs: [URL]

        var body: some View {
            VStack {
                // Display current image
                DicomImageView(viewModel: imageVM)

                // Navigation controls
                SeriesNavigatorView(
                    navigatorViewModel: navigatorVM,
                    onNavigate: { url in
                        Task {
                            await imageVM.loadImage(from: url)
                        }
                    }
                )
            }
            .onAppear {
                navigatorVM.setSeriesURLs(seriesURLs)
                if let firstURL = navigatorVM.currentURL {
                    Task {
                        await imageVM.loadImage(from: firstURL)
                    }
                }
            }
        }
    }

    let urls = (1...100).map { URL(fileURLWithPath: "/path/to/series/slice\($0).dcm") }
    return BasicSeriesView(seriesURLs: urls)
}

/// A compact example view that displays a DICOM image alongside a compact series navigator.
/// 
/// The view shows a DicomImageView above a compact SeriesNavigatorView. It initializes the navigator with a sample set of 50 placeholder series URLs, loads the first image on appear, and loads the selected image whenever the navigator changes selection.
/// Creates a compact SwiftUI example view that displays a DICOM image alongside a compact series navigator.
/// 
/// The view initializes a SeriesNavigatorViewModel and DicomImageViewModel, sets the navigator with a prebuilt set of 50 placeholder slice URLs on appear, and loads the first image if available. Tapping or navigating in the navigator loads the selected slice into the image view.
/// - Returns: A view containing a DicomImageView (fixed height) and a compact SeriesNavigatorView wired to load selected slices.
func compactSeriesNavigator() -> some View {
    struct CompactSeriesView: View {
        @StateObject private var navigatorVM = SeriesNavigatorViewModel()
        @StateObject private var imageVM = DicomImageViewModel()
        let seriesURLs: [URL]

        var body: some View {
            VStack(spacing: 8) {
                DicomImageView(viewModel: imageVM)
                    .frame(height: 400)

                SeriesNavigatorView(
                    navigatorViewModel: navigatorVM,
                    layout: .compact,
                    onNavigate: { url in
                        Task {
                            await imageVM.loadImage(from: url)
                        }
                    }
                )
                .padding(8)
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(8)
            }
            .onAppear {
                navigatorVM.setSeriesURLs(seriesURLs)
                if let firstURL = navigatorVM.currentURL {
                    Task {
                        await imageVM.loadImage(from: firstURL)
                    }
                }
            }
        }
    }

    let urls = (1...50).map { URL(fileURLWithPath: "/path/to/series/slice\($0).dcm") }
    return CompactSeriesView(seriesURLs: urls)
}

// MARK: - Loading Series from Directory

/// Creates a view that loads a DICOM series from a local directory and presents it with navigation.
/// 
/// The view scans a predefined directory for files with `.dcm` or `.dicom` extensions, displays a loading indicator while the directory is being read, loads the first image found, and provides a series navigator to load other images in the series.
/// - Returns: A SwiftUI view that loads DICOM files from a local directory, shows a loading state while scanning, and displays the first image along with a series navigator.
func loadSeriesFromDirectory() -> some View {
    struct DirectorySeriesView: View {
        @StateObject private var navigatorVM = SeriesNavigatorViewModel()
        @StateObject private var imageVM = DicomImageViewModel()
        @State private var isLoading = true
        let directoryURL: URL

        var body: some View {
            VStack {
                if isLoading {
                    ProgressView("Loading series...")
                } else {
                    DicomImageView(viewModel: imageVM)

                    SeriesNavigatorView(
                        navigatorViewModel: navigatorVM,
                        onNavigate: { url in
                            Task {
                                await imageVM.loadImage(from: url)
                            }
                        }
                    )
                }
            }
            .task {
                await loadSeriesFromDirectory()
            }
        }

        /// Loads DICOM files from `directoryURL`, updates the series navigator with the found files, and loads the first image.
        /// Loads DICOM files from `directoryURL`, populates the series navigator, and loads the first image if available.
        ///
        /// The method scans `directoryURL` for files with `.dcm` or `.dicom` extensions, sorts them by filename, and calls `navigatorVM.setSeriesURLs(_:)` with the resulting URLs. If a first URL is available it requests `imageVM` to load that image. The `isLoading` flag is cleared when the operation finishes or if an error occurs; errors are logged to the console.
        private func loadSeriesFromDirectory() async {
            do {
                let fileManager = FileManager.default
                let files = try fileManager.contentsOfDirectory(
                    at: directoryURL,
                    includingPropertiesForKeys: nil
                )

                // Filter DICOM files
                let dicomFiles = files.filter {
                    $0.pathExtension.lowercased() == "dcm" ||
                    $0.pathExtension.lowercased() == "dicom"
                }.sorted { $0.lastPathComponent < $1.lastPathComponent }

                navigatorVM.setSeriesURLs(dicomFiles)

                if let firstURL = navigatorVM.currentURL {
                    await imageVM.loadImage(from: firstURL)
                }

                isLoading = false
            } catch {
                print("Error loading series: \(error)")
                isLoading = false
            }
        }
    }

    return DirectorySeriesView(directoryURL: URL(fileURLWithPath: "/path/to/series/"))
}

// MARK: - Series with Windowing

/// Demonstrates a SwiftUI example that combines series navigation with windowing controls for DICOM images.
/// Builds a sample SwiftUI view that displays a DICOM series with integrated series navigation and window/level controls.
/// 
/// The returned view shows an image viewer, a compact series navigator that loads the selected slice, and compact windowing controls that apply custom window/level settings to the current image. The view initializes the navigator with a preset series and loads the first slice when it appears.
/// - Returns: A view configured for series navigation and interactive windowing controls.
func seriesWithWindowing() -> some View {
    struct SeriesWindowingView: View {
        @StateObject private var navigatorVM = SeriesNavigatorViewModel()
        @StateObject private var windowingVM = WindowingViewModel()
        @StateObject private var imageVM = DicomImageViewModel()
        let seriesURLs: [URL]

        var body: some View {
            VStack(spacing: 0) {
                // Image display
                DicomImageView(viewModel: imageVM)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.black)

                // Series navigation
                SeriesNavigatorView(
                    navigatorViewModel: navigatorVM,
                    layout: .compact,
                    onNavigate: { url in
                        Task {
                            await imageVM.loadImage(from: url)
                        }
                    }
                )
                .padding(.horizontal)
                .background(platformSystemBackground)

                // Windowing controls
                WindowingControlView(
                    windowingViewModel: windowingVM,
                    layout: .compact,
                    onWindowingChanged: { settings in
                        Task {
                            await imageVM.updateWindowing(
                                windowingMode: .custom(
                                    center: settings.center,
                                    width: settings.width
                                )
                            )
                        }
                    }
                )
                .padding(.horizontal)
                .background(platformSystemBackground)
            }
            .onAppear {
                navigatorVM.setSeriesURLs(seriesURLs)
                if let firstURL = navigatorVM.currentURL {
                    Task {
                        await imageVM.loadImage(from: firstURL)
                    }
                }
            }
        }
    }

    let urls = (1...150).map { URL(fileURLWithPath: "/path/to/ct_series/slice\($0).dcm") }
    return SeriesWindowingView(seriesURLs: urls)
}

// MARK: - Keyboard Shortcuts

/// Displays a DICOM image alongside a series navigator that supports arrow-key navigation.
/// Displays a DICOM series viewer with keyboard arrow navigation enabled.
/// 
/// The view shows the current DICOM image, a series navigator configured to accept keyboard shortcuts, and a small caption. On appear it initializes the navigator with the provided series and loads the first image; selecting a slice via the navigator loads that image into the viewer.
/// - Returns: A view containing a DICOM image display and a series navigator with keyboard shortcuts enabled.
func keyboardShortcutNavigation() -> some View {
    struct KeyboardNavigationView: View {
        @StateObject private var navigatorVM = SeriesNavigatorViewModel()
        @StateObject private var imageVM = DicomImageViewModel()
        let seriesURLs: [URL]

        var body: some View {
            VStack {
                DicomImageView(viewModel: imageVM)

                SeriesNavigatorView(
                    navigatorViewModel: navigatorVM,
                    onNavigate: { url in
                        Task {
                            await imageVM.loadImage(from: url)
                        }
                    }
                )

                Text("Use arrow keys to navigate")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .onAppear {
                navigatorVM.setSeriesURLs(seriesURLs)
                if let firstURL = navigatorVM.currentURL {
                    Task {
                        await imageVM.loadImage(from: firstURL)
                    }
                }
            }
        }
    }

    let urls = (1...100).map { URL(fileURLWithPath: "/path/to/series/slice\($0).dcm") }
    return KeyboardNavigationView(seriesURLs: urls)
}

// MARK: - Navigation State Management

/// Presents an example view that tracks and displays recent navigation history while browsing a DICOM series.
/// 
/// The returned view shows the currently loaded DICOM image, a horizontal list of recently visited slice indices (up to 10 entries), and series navigation controls. Selecting a history entry or using the navigator updates the displayed image and the history.
/// - Returns: A SwiftUI view combining a DICOM image display, series navigator, and a horizontal navigation history showing up to 10 recent indices.
func trackNavigationState() -> some View {
    struct NavigationTrackerView: View {
        @StateObject private var navigatorVM = SeriesNavigatorViewModel()
        @StateObject private var imageVM = DicomImageViewModel()
        @State private var navigationHistory: [Int] = []
        let seriesURLs: [URL]

        var body: some View {
            VStack {
                DicomImageView(viewModel: imageVM)

                VStack(spacing: 8) {
                    Text("Navigation History")
                        .font(.headline)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(navigationHistory, id: \.self) { index in
                                Button("\(index + 1)") {
                                    navigatorVM.goToIndex(index)
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                    }
                    .frame(height: 40)
                }
                .padding()

                SeriesNavigatorView(
                    navigatorViewModel: navigatorVM,
                    onNavigate: { url in
                        // Track navigation
                        navigationHistory.append(navigatorVM.currentIndex)
                        if navigationHistory.count > 10 {
                            navigationHistory.removeFirst()
                        }

                        Task {
                            await imageVM.loadImage(from: url)
                        }
                    }
                )
            }
            .onAppear {
                navigatorVM.setSeriesURLs(seriesURLs)
                if let firstURL = navigatorVM.currentURL {
                    navigationHistory.append(0)
                    Task {
                        await imageVM.loadImage(from: firstURL)
                    }
                }
            }
        }
    }

    let urls = (1...100).map { URL(fileURLWithPath: "/path/to/series/slice\($0).dcm") }
    return NavigationTrackerView(seriesURLs: urls)
}

// MARK: - Lazy Loading

/// Demonstrates lazy loading of a DICOM series with a bounded in-memory cache during navigation.
/// 
/// Presents a SwiftUI view that displays the current DICOM image, series navigation controls, and a cached-image count. Images are loaded on demand as the user navigates and cached by index to avoid reloading nearby slices.
/// Creates a SwiftUI example view that demonstrates per-slice lazy loading and bounded in-memory caching for a DICOM series.
/// 
/// The returned view combines a DicomImageView, a SeriesNavigatorView, and a small status showing how many slices have been cached. It initializes a navigator with a set of example URLs, loads the first image on appear, and caches loaded `CGImage` objects by series index for reuse when navigating.
/// - Returns: A view configured with a series navigator, an image display, and a per-slice `CGImage` cache with a cached-count indicator.
func lazyLoadingNavigation() -> some View {
    struct LazyLoadingView: View {
        @StateObject private var navigatorVM = SeriesNavigatorViewModel()
        @StateObject private var imageVM = DicomImageViewModel()
        @State private var loadedImages: [Int: CGImage] = [:]
        @State private var loadedDecoders: [Int: DCMDecoder] = [:]
        private let cacheRadius = 10
        let seriesURLs: [URL]

        var body: some View {
            VStack {
                DicomImageView(viewModel: imageVM)

                Text("Cached: \(loadedImages.count) / \(seriesURLs.count) images")
                    .font(.caption)
                    .foregroundColor(.secondary)

                SeriesNavigatorView(
                    navigatorViewModel: navigatorVM,
                    onNavigate: { url in
                        Task {
                            let currentIndex = await MainActor.run { navigatorVM.currentIndex }
                            await loadImageWithCache(url: url, index: currentIndex)
                        }
                    }
                )
            }
            .onAppear {
                Task {
                    let firstURL = await MainActor.run { () -> URL? in
                        navigatorVM.setSeriesURLs(seriesURLs)
                        return navigatorVM.currentURL
                    }
                    if let firstURL {
                        await loadImageWithCache(url: firstURL, index: 0)
                    }
                }
            }
        }

        /// Loads the image for a given series URL and index, preferring a cached image and caching the result.
        /// 
        /// If a cached image/decoder exists for `index`, it re-renders from the cached decoder and returns early. Otherwise it loads and decodes from disk, then stores both the rendered image and decoder in cache dictionaries keyed by `index`.
        /// - Parameters:
        ///   - url: The file URL of the image to load.
        /// Ensures the image for the given URL is available in the in-memory cache and updates the shared image view model.
        /// 
        /// If a cached image exists for `index`, this function short-circuits by loading from the cached decoder so the UI uses cached data instead of re-reading from disk. On cache miss, it decodes from file and stores both decoder and rendered image in cache.
        /// - Parameters:
        ///   - url: The source URL of the DICOM image to load.
        ///   - index: The numeric index used as the cache key for this image.
        private func loadImageWithCache(url: URL, index: Int) async {
            // Check cache first
            let cachedDecoder: DCMDecoder? = await MainActor.run {
                guard loadedImages[index] != nil else { return nil }
                return loadedDecoders[index]
            }
            if let cachedDecoder {
                print("Using cached image for index \(index)")
                await imageVM.loadImage(decoder: cachedDecoder)
                return
            }

            // Load and cache
            do {
                let decoder = try await DCMDecoder(contentsOfFile: url.path)
                await imageVM.loadImage(decoder: decoder)

                let renderedImage = await MainActor.run { imageVM.image }
                if let renderedImage {
                    await MainActor.run {
                        loadedImages[index] = renderedImage
                        loadedDecoders[index] = decoder

                        // Keep only nearby slices cached to avoid unbounded memory growth.
                        let lowerBound = max(0, index - cacheRadius)
                        let upperBound = min(seriesURLs.count - 1, index + cacheRadius)
                        let keepRange = lowerBound...upperBound
                        loadedImages = loadedImages.filter { keepRange.contains($0.key) }
                        loadedDecoders = loadedDecoders.filter { keepRange.contains($0.key) }
                    }
                }
            } catch {
                print("Failed to load image at index \(index): \(error)")
            }
        }
    }

    let urls = (1...50).map { URL(fileURLWithPath: "/path/to/series/slice\($0).dcm") }
    return LazyLoadingView(seriesURLs: urls)
}

// MARK: - Preloading Adjacent Slices

/// A SwiftUI example view that displays a DICOM image and preloads adjacent slices for smoother navigation.
/// 
/// The view renders the current image, a series navigator control, and a small indicator of how many slices have been preloaded. When navigating, it loads the selected slice and asynchronously preloads nearby slices into an in-memory decoder cache, pruning decoders that are far from the current index.
/// - Returns: A SwiftUI view containing the DICOM image display, a series navigator, and a preloaded-images count indicator.
func preloadAdjacentSlices() -> some View {
    struct PreloadingView: View {
        @StateObject private var navigatorVM = SeriesNavigatorViewModel()
        @StateObject private var imageVM = DicomImageViewModel()
        @State private var preloadedDecoders: [Int: DCMDecoder] = [:]
        let seriesURLs: [URL]

        var body: some View {
            VStack {
                DicomImageView(viewModel: imageVM)

                Text("Preloaded: \(preloadedDecoders.count) images")
                    .font(.caption)
                    .foregroundColor(.secondary)

                SeriesNavigatorView(
                    navigatorViewModel: navigatorVM,
                    onNavigate: { url in
                        Task {
                            await loadWithPreloading(index: navigatorVM.currentIndex)
                        }
                    }
                )
            }
            .onAppear {
                navigatorVM.setSeriesURLs(seriesURLs)
                Task {
                    await loadWithPreloading(index: 0)
                }
            }
        }

        /// Load the image at the given series index, preferring an already preloaded decoder if available, and start background preloading of adjacent slices.
        /// Loads the image for the given slice index into the image view model and begins background preloading of adjacent slices.
        /// - Parameter index: The index of the slice to display within `seriesURLs`. If a decoder for this index exists in `preloadedDecoders`, it will be used; otherwise the image is loaded from the corresponding URL.
        private func loadWithPreloading(index: Int) async {
            // Load current image
            if let decoder = preloadedDecoders[index] {
                await imageVM.loadImage(decoder: decoder)
            } else {
                await imageVM.loadImage(from: seriesURLs[index])
            }

            // Preload adjacent slices in background
            Task {
                await preloadSlices(around: index)
            }
        }

        /// Preloads decoders for image slices near a given index and prunes cached decoders far from that index.
        /// 
        /// Attempts to create and cache a `DCMDecoder` for up to two slices before and after `index`, skipping out-of-bounds indices and indices that are already cached. After preloading, removes cached decoders whose indices are outside the window from `index - 5` to `index + 5`.
        /// Preloads decoder objects for slices near a given index and prunes distant cached decoders.
        /// 
        /// Loads decoder instances for up to two slices before and after the provided `index`, skipping indices that are out of range or already preloaded. Errors during individual preloads are logged but do not stop the overall operation. After preloading, removes cached decoders whose indices are outside the range `index - 5` through `index + 5`.
        /// - Parameter index: The current slice index around which to preload decoders.
        private func preloadSlices(around index: Int) async {
            let preloadRange = 2 // Preload 2 slices before and after

            for offset in -preloadRange...preloadRange {
                let targetIndex = index + offset
                guard targetIndex >= 0, targetIndex < seriesURLs.count else {
                    continue
                }

                let shouldPreload = await MainActor.run {
                    preloadedDecoders[targetIndex] == nil
                }
                guard shouldPreload else {
                    continue
                }

                do {
                    let decoder = try await DCMDecoder(contentsOfFile: seriesURLs[targetIndex].path)
                    await MainActor.run {
                        preloadedDecoders[targetIndex] = decoder
                    }
                } catch {
                    print("Failed to preload slice \(targetIndex): \(error)")
                }
            }

            // Clean up distant slices
            let keepRange = (max(0, index - 5))...(min(seriesURLs.count - 1, index + 5))
            await MainActor.run {
                preloadedDecoders = preloadedDecoders.filter { keepRange.contains($0.key) }
            }
        }
    }

    let urls = (1...100).map { URL(fileURLWithPath: "/path/to/series/slice\($0).dcm") }
    return PreloadingView(seriesURLs: urls)
}

// MARK: - Multi-Series Navigation

/// Presents a UI for switching between and navigating multiple DICOM series.
/// 
/// The view shows a segmented picker to select a series and a paged TabView where each tab contains a DICOM image display and a series navigator. Selecting a series or navigating within a series loads the corresponding image into a shared image view model so the same image view is reused across series tabs.
/// Displays a multi-series DICOM viewer with a segmented series selector and paged tabs.
/// 
/// Each tab presents a DICOM image view paired with a series navigator; selecting a segment or page switches the active series and shows its images.
/// - Returns: A SwiftUI view containing a segmented picker for choosing a series and a paged TabView where each page hosts the image display and navigator for that series.
func multiSeriesNavigation() -> some View {
    struct MultiSeriesView: View {
        @StateObject private var imageVM = DicomImageViewModel()
        @State private var selectedSeriesIndex = 0
        let allSeries: [[URL]]

        var body: some View {
            VStack(spacing: 0) {
                // Series selector
                Picker("Series", selection: $selectedSeriesIndex) {
                    ForEach(0..<allSeries.count, id: \.self) { index in
                        Text("Series \(index + 1) (\(allSeries[index].count) images)")
                            .tag(index)
                    }
                }
                .pickerStyle(.segmented)
                .padding()
                .background(platformSystemBackground)

                // Image display with current series navigator
                TabView(selection: $selectedSeriesIndex) {
                    ForEach(0..<allSeries.count, id: \.self) { seriesIndex in
                        SeriesViewTab(
                            seriesURLs: allSeries[seriesIndex],
                            imageVM: imageVM
                        )
                        .tag(seriesIndex)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
            }
        }
    }

    struct SeriesViewTab: View {
        @StateObject private var navigatorVM = SeriesNavigatorViewModel()
        let seriesURLs: [URL]
        @ObservedObject var imageVM: DicomImageViewModel

        var body: some View {
            VStack {
                DicomImageView(viewModel: imageVM)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                SeriesNavigatorView(
                    navigatorViewModel: navigatorVM,
                    onNavigate: { url in
                        Task {
                            await imageVM.loadImage(from: url)
                        }
                    }
                )
            }
            .onAppear {
                navigatorVM.setSeriesURLs(seriesURLs)
                if let firstURL = navigatorVM.currentURL {
                    Task {
                        await imageVM.loadImage(from: firstURL)
                    }
                }
            }
        }
    }

    let series1 = (1...50).map { URL(fileURLWithPath: "/path/to/series1/slice\($0).dcm") }
    let series2 = (1...75).map { URL(fileURLWithPath: "/path/to/series2/slice\($0).dcm") }
    let series3 = (1...100).map { URL(fileURLWithPath: "/path/to/series3/slice\($0).dcm") }

    return MultiSeriesView(allSeries: [series1, series2, series3])
}

// MARK: - Cine Loop (Animated Playback)

/// Creates a view that plays a DICOM series as a cine loop with playback controls and adjustable speed.
/// 
/// The view shows the current DICOM image, a play/pause button, an FPS slider, and a series navigator. When playing, it advances through the series at the selected frames-per-second rate and loops back to the first image after the last.
/// Creates a SwiftUI view that demonstrates cine-style playback of a DICOM series with playback controls and a series navigator.
/// The view loads the first image on appear, provides play/pause and FPS controls, and advances through images at the selected speed, looping to the first image after the last.
/// - Returns: A view that displays DICOM images with play/pause controls, a speed slider (frames per second), and a series navigator; playback advances frames at the selected FPS and continues until paused.
func cineLoopPlayback() -> some View {
    struct CineLoopView: View {
        @StateObject private var navigatorVM = SeriesNavigatorViewModel()
        @StateObject private var imageVM = DicomImageViewModel()
        @State private var isPlaying = false
        @State private var playbackSpeed: Double = 10.0 // FPS
        let seriesURLs: [URL]

        var body: some View {
            VStack {
                DicomImageView(viewModel: imageVM)

                // Playback controls
                HStack(spacing: 16) {
                    Button(action: { isPlaying.toggle() }) {
                        Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                            .font(.title2)
                    }
                    .buttonStyle(.borderedProminent)

                    VStack {
                        Text("Speed: \(Int(playbackSpeed)) FPS")
                            .font(.caption)

                        Slider(value: $playbackSpeed, in: 1...30, step: 1)
                            .frame(width: 150)
                    }
                }
                .padding()

                SeriesNavigatorView(
                    navigatorViewModel: navigatorVM,
                    onNavigate: { url in
                        Task {
                            await imageVM.loadImage(from: url)
                        }
                    }
                )
            }
            .onAppear {
                navigatorVM.setSeriesURLs(seriesURLs)
                if let firstURL = navigatorVM.currentURL {
                    Task {
                        await imageVM.loadImage(from: firstURL)
                    }
                }
            }
            .onChange(of: isPlaying) { newValue in
                if newValue {
                    startPlayback()
                }
            }
        }

        /// Starts asynchronous playback of the series, advancing to the next image repeatedly at a rate defined by `playbackSpeed`.
        /// Start the cine playback loop, advancing the navigator at the configured playback speed.
        /// 
        /// Begins an asynchronous loop that advances to the next image at each interval and wraps to the first image when the end is reached. The loop continues until `isPlaying` becomes false. The delay between frames is derived from `playbackSpeed`.
        private func startPlayback() {
            guard isPlaying else { return }

            Task { @MainActor in
                while isPlaying && !Task.isCancelled {
                    navigatorVM.goToNext()

                    if navigatorVM.isAtLast {
                        navigatorVM.goToFirst()
                    }

                    if Task.isCancelled || !isPlaying {
                        break
                    }
                    try? await Task.sleep(nanoseconds: UInt64(1_000_000_000 / playbackSpeed))
                }
            }
        }
    }

    let urls = (1...50).map { URL(fileURLWithPath: "/path/to/series/slice\($0).dcm") }
    return CineLoopView(seriesURLs: urls)
}

// MARK: - Complete Series Viewer

/// Presents a complete DICOM series viewer with image display, navigation, window/level controls, metadata presentation, and export action.
/// 
/// The view shows the current image, a series navigator, compact windowing controls, and an optional series information banner. A toolbar menu provides actions to toggle the series info banner, open a metadata sheet for the current image, and trigger an export action. When the view appears it initializes the navigator with a provided series and loads the first image.
/// Creates a full-featured example viewer for browsing and inspecting a DICOM series.
/// 
/// The returned view displays a DICOM image, a series navigator, compact window/level controls, an optional series information banner, a metadata sheet for the current image, and a toolbar menu with a stubbed export action. The viewer initializes its navigator with a provided list of slice URLs and loads the first image on appear.
/// - Returns: A SwiftUI view configured as a complete DICOM series viewer example.
func completeSeriesViewer() -> some View {
    struct CompleteSeriesViewer: View {
        @StateObject private var navigatorVM = SeriesNavigatorViewModel()
        @StateObject private var windowingVM = WindowingViewModel()
        @StateObject private var imageVM = DicomImageViewModel()
        @State private var showingMetadata = false
        @State private var metadataDecoder: DCMDecoder?
        @State private var isLoadingMetadata = false
        @State private var metadataError: Error?
        @State private var showingSeriesInfo = false
        let seriesURLs: [URL]

        var body: some View {
            NavigationView {
                VStack(spacing: 0) {
                    // Image display
                    DicomImageView(viewModel: imageVM)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.black)

                    // Series information banner
                    if showingSeriesInfo {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Series Information")
                                    .font(.headline)
                                Text("\(navigatorVM.totalCount) images")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }

                            Spacer()

                            Button("Hide") {
                                showingSeriesInfo = false
                            }
                            .font(.caption)
                        }
                        .padding()
                        .background(Color.secondary.opacity(0.1))
                    }

                    // Navigation controls
                    SeriesNavigatorView(
                        navigatorViewModel: navigatorVM,
                        onNavigate: { url in
                            Task {
                                await imageVM.loadImage(from: url)
                            }
                        }
                    )
                    .background(platformSystemBackground)

                    // Windowing controls
                    WindowingControlView(
                        windowingViewModel: windowingVM,
                        layout: .compact,
                        onWindowingChanged: { settings in
                            Task {
                                await imageVM.updateWindowing(
                                    windowingMode: .custom(
                                        center: settings.center,
                                        width: settings.width
                                    )
                                )
                            }
                        }
                    )
                    .background(platformSystemBackground)
                }
                .navigationTitle("Series Viewer")
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Menu {
                            Button(action: { showingSeriesInfo.toggle() }) {
                                Label("Series Info", systemImage: "info.circle")
                            }

                            Button(action: { showingMetadata = true }) {
                                Label("Metadata", systemImage: "doc.text")
                            }

                            Divider()

                            Button(action: exportSeries) {
                                Label("Export Series", systemImage: "square.and.arrow.up")
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                    }
                }
                .sheet(isPresented: $showingMetadata) {
                    NavigationView {
                        Group {
                            if let metadataDecoder = metadataDecoder {
                                MetadataView(decoder: metadataDecoder)
                            } else if isLoadingMetadata {
                                ProgressView("Loading metadata...")
                            } else if let metadataError = metadataError {
                                Text("Failed to load metadata: \(metadataError.localizedDescription)")
                                    .foregroundColor(.red)
                                    .padding()
                            } else {
                                Text("No metadata available")
                                    .foregroundColor(.secondary)
                            }
                        }
                        .navigationTitle("Current Image Metadata")
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Done") {
                                    showingMetadata = false
                                }
                            }
                        }
                    }
                }
            }
            .onAppear {
                navigatorVM.setSeriesURLs(seriesURLs)
                if let firstURL = navigatorVM.currentURL {
                    Task {
                        await imageVM.loadImage(from: firstURL)
                    }
                }
            }
            .onChange(of: showingMetadata) { isPresented in
                if isPresented {
                    loadMetadataForCurrentImage()
                } else {
                    metadataDecoder = nil
                    metadataError = nil
                    isLoadingMetadata = false
                }
            }
        }

        private func loadMetadataForCurrentImage() {
            guard let currentURL = navigatorVM.currentURL else {
                metadataDecoder = nil
                metadataError = nil
                isLoadingMetadata = false
                return
            }
            let targetURL = currentURL

            metadataDecoder = nil
            metadataError = nil
            isLoadingMetadata = true

            Task {
                do {
                    let loadedDecoder = try await DCMDecoder(contentsOfFile: targetURL.path)
                    let isStillRelevant = await MainActor.run {
                        showingMetadata && navigatorVM.currentURL?.path == targetURL.path
                    }
                    guard isStillRelevant else { return }

                    await MainActor.run {
                        metadataDecoder = loadedDecoder
                        metadataError = nil
                        isLoadingMetadata = false
                    }
                } catch {
                    let isStillRelevant = await MainActor.run {
                        showingMetadata && navigatorVM.currentURL?.path == targetURL.path
                    }
                    guard isStillRelevant else { return }

                    await MainActor.run {
                        metadataDecoder = nil
                        metadataError = error
                        isLoadingMetadata = false
                    }
                }
            }
        }

        /// Initiates an export of the currently loaded DICOM series.
        /// 
        /// Initiates export of the currently selected DICOM series to an external destination.
        /// 
        /// The operation should write all images from the active series (as represented by the navigator) to a user-chosen location or package them for export.
        private func exportSeries() {
            print("Exporting series with \(navigatorVM.totalCount) images")
            // Implement export functionality
        }
    }

    let urls = (1...150).map { URL(fileURLWithPath: "/path/to/ct_series/slice\($0).dcm") }
    return CompleteSeriesViewer(seriesURLs: urls)
}

// MARK: - Loading Series with DicomSeriesLoader

/// Creates a SwiftUI view that loads DICOM files from a directory and presents the series with an image display and navigation controls.
/// 
/// While the series is being discovered and validated, a progress indicator is shown. After loading completes the view populates the navigator and displays the first image; if loading fails the loading state is cleared and the view stops showing the progress indicator.
/// Loads DICOM files from `seriesDirectory`, validates them with `DicomSeriesLoader`, initializes the navigator with deterministic file ordering, loads the first image into `imageVM` if present, and clears the loading state.
/// 
/// On success, `navigatorVM` is populated with sorted URLs and the first image is loaded into `imageVM`. On failure, the error is printed and `isLoading` is set to `false`.
func orderedSeriesLoading(
    loaderFactory: @escaping () -> DicomSeriesLoaderProtocol = { DicomSeriesLoader() }
) -> some View {
    struct OrderedSeriesView: View {
        @StateObject private var navigatorVM = SeriesNavigatorViewModel()
        @StateObject private var imageVM = DicomImageViewModel()
        @State private var isLoading = true
        let seriesDirectory: URL
        let loaderFactory: () -> DicomSeriesLoaderProtocol

        var body: some View {
            VStack {
                if isLoading {
                    ProgressView("Loading and ordering series...")
                } else {
                    DicomImageView(viewModel: imageVM)

                    SeriesNavigatorView(
                        navigatorViewModel: navigatorVM,
                        onNavigate: { url in
                            Task {
                                await imageVM.loadImage(from: url)
                            }
                        }
                    )
                }
            }
            .task {
                await loadOrderedSeries()
            }
        }

        /// Load DICOM files from `seriesDirectory`, validate the series, and initialize the navigator and image view models.
        ///
        /// Discover and load a DICOM series from the configured directory.
        ///
        /// Scans `seriesDirectory` for files with `.dcm` or `.dicom` extensions, validates and loads volume metadata with `DicomSeriesLoader`, updates `navigatorVM` with deterministic file ordering, and loads the first image into `imageVM` if available. Clears the `isLoading` flag when finished; on failure, clears `isLoading` and prints the encountered error.
        private func loadOrderedSeries() async {
            do {
                // Get all DICOM files in directory
                let fileManager = FileManager.default
                let files = try fileManager.contentsOfDirectory(
                    at: seriesDirectory,
                    includingPropertiesForKeys: nil
                )

                let dicomFiles = files.filter {
                    $0.pathExtension.lowercased() == "dcm" ||
                    $0.pathExtension.lowercased() == "dicom"
                }

                let loader = loaderFactory()
                let seriesInfo = try await loader.loadSeries(in: seriesDirectory)

                // Navigator still needs file URLs; use deterministic name ordering.
                let orderedURLs = dicomFiles.sorted {
                    $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending
                }

                navigatorVM.setSeriesURLs(orderedURLs)

                if let firstURL = navigatorVM.currentURL {
                    await imageVM.loadImage(from: firstURL)
                }

                print(
                    """
                    Loaded volume: \(seriesInfo.depth) slices \
                    (\(seriesInfo.width)x\(seriesInfo.height)), \
                    spacing=\(seriesInfo.spacing.x)x\(seriesInfo.spacing.y)x\(seriesInfo.spacing.z)
                    """
                )

                isLoading = false
            } catch {
                print("Error loading series: \(error)")
                isLoading = false
            }
        }
    }

    return OrderedSeriesView(
        seriesDirectory: URL(fileURLWithPath: "/path/to/series/"),
        loaderFactory: loaderFactory
    )
}
