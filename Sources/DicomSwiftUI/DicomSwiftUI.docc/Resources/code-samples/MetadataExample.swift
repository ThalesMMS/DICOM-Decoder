import SwiftUI
import DicomSwiftUI
import DicomCore
#if os(iOS) || os(tvOS) || os(visionOS)
import UIKit
#endif

/// DocC Preface
/// - Platform support: iOS 13.0+ and macOS 12.0+.
/// - Recommended loading pattern: use `Task`/`.task` with `try await DCMDecoder(contentsOfFile:)`.
/// - Deprecated pattern: synchronous `DCMDecoder(contentsOf:)` / `DCMDecoder(contentsOfFile:)`.
/// - Migration hint: move decoder creation into an async function called from `.task`,
///   store the result in `@State`, and render loading/error states while awaiting I/O.

private extension View {
    @ViewBuilder
    func inlineNavigationBarTitle() -> some View {
#if os(iOS) || os(tvOS)
        self.navigationBarTitleDisplayMode(.inline)
#else
        self
#endif
    }
}

// MARK: - Basic Metadata Display

/// Creates a simple example view that displays DICOM metadata from a local file.
/// 
/// The view attempts to initialize a `DCMDecoder` from the hard-coded file path and presents a `MetadataView` when successful. If decoder initialization fails, the view shows a `Text` describing the loading error.
/// Creates a view that displays DICOM metadata loaded from a local file or an error message if loading fails.
/// - Returns: A view that contains `MetadataView` initialized with the DICOM file at `/path/to/ct_scan.dcm` on success, or a `Text` view describing the load error on failure.
func simpleMetadataDisplay() -> some View {
    struct SimpleMetadataView: View {
        let filePath: String
        @State private var decoder: DCMDecoder?
        @State private var loadError: String?

        var body: some View {
            Group {
                if let decoder = decoder {
                    MetadataView(decoder: decoder)
                } else if let loadError = loadError {
                    Text("Failed to load: \(loadError)")
                } else {
                    ProgressView("Loading metadata...")
                }
            }
            .task(id: filePath) {
                await loadDecoder()
            }
        }

        private func loadDecoder() async {
            await MainActor.run {
                decoder = nil
                loadError = nil
            }

            do {
                let loadedDecoder = try await DCMDecoder(contentsOfFile: filePath)
                await MainActor.run {
                    decoder = loadedDecoder
                }
            } catch {
                await MainActor.run {
                    decoder = nil
                    loadError = error.localizedDescription
                }
            }
        }
    }

    return SimpleMetadataView(filePath: "/path/to/ct_scan.dcm")
}

/// Presents DICOM metadata inside a navigation-style view.
/// 
/// Attempts to create a `DCMDecoder` from a bundled file and returns a view that displays `MetadataView` embedded in a `NavigationView` with the title "DICOM Metadata". If the decoder cannot be created, returns a `Text` view showing the error description.
/// Creates a NavigationView that displays DICOM metadata with the title "DICOM Metadata".
/// - Returns: A view that shows `MetadataView` wrapped in a `NavigationView` titled "DICOM Metadata" when the DICOM file loads successfully; a `Text` view containing the load error message if the decoder fails to initialize.
func metadataInNavigation() -> some View {
    struct MetadataNavigationView: View {
        let filePath: String
        @State private var decoder: DCMDecoder?
        @State private var loadError: String?

        var body: some View {
            NavigationView {
                Group {
                    if let decoder = decoder {
                        MetadataView(decoder: decoder)
                    } else if let loadError = loadError {
                        Text("Error: \(loadError)")
                    } else {
                        ProgressView("Loading metadata...")
                    }
                }
                .navigationTitle("DICOM Metadata")
                .inlineNavigationBarTitle()
            }
            .task(id: filePath) {
                await loadDecoder()
            }
        }

        private func loadDecoder() async {
            await MainActor.run {
                decoder = nil
                loadError = nil
            }

            do {
                let loadedDecoder = try await DCMDecoder(contentsOfFile: filePath)
                await MainActor.run {
                    decoder = loadedDecoder
                }
            } catch {
                await MainActor.run {
                    decoder = nil
                    loadError = error.localizedDescription
                }
            }
        }
    }

    return MetadataNavigationView(filePath: "/path/to/image.dcm")
}

// MARK: - Presentation Styles

/// Displays DICOM metadata in a form-style NavigationView.
/// 
/// Attempts to initialize a `DCMDecoder` from a bundled file and presents `MetadataView` with the `.form` style inside a `NavigationView`. If the decoder cannot be created, a `Text` view with an error message is returned.
/// Creates a NavigationView presenting DICOM metadata using a form-style layout.
/// - Returns: A view that displays the DICOM file's metadata in a form-styled `MetadataView` inside a `NavigationView`; if the DICOM file cannot be loaded, returns a `Text` view indicating the load error.
func formStyleMetadata() -> some View {
    struct FormMetadataView: View {
        let filePath: String
        @State private var decoder: DCMDecoder?
        @State private var loadError: String?

        var body: some View {
            NavigationView {
                Group {
                    if let decoder = decoder {
                        MetadataView(decoder: decoder, style: .form)
                    } else if let loadError = loadError {
                        Text("Error loading metadata: \(loadError)")
                    } else {
                        ProgressView("Loading metadata...")
                    }
                }
                .navigationTitle("DICOM Information")
                .inlineNavigationBarTitle()
            }
            .task(id: filePath) {
                await loadDecoder()
            }
        }

        private func loadDecoder() async {
            await MainActor.run {
                decoder = nil
                loadError = nil
            }

            do {
                let loadedDecoder = try await DCMDecoder(contentsOfFile: filePath)
                await MainActor.run {
                    decoder = loadedDecoder
                }
            } catch {
                await MainActor.run {
                    decoder = nil
                    loadError = error.localizedDescription
                }
            }
        }
    }

    return FormMetadataView(filePath: "/path/to/mr_scan.dcm")
}

/// Create a SwiftUI view that displays DICOM metadata using a list-style presentation.
/// Creates a navigation-wrapped view that displays DICOM metadata using a list-style presentation.
/// - Returns: A view that shows the DICOM metadata in a list-style `MetadataView` when the DICOM file at `/path/to/image.dcm` can be decoded; otherwise a `Text` view indicating an error loading metadata.
func listStyleMetadata() -> some View {
    struct ListMetadataView: View {
        let filePath: String
        @State private var decoder: DCMDecoder?
        @State private var loadError: String?

        var body: some View {
            NavigationView {
                Group {
                    if let decoder = decoder {
                        MetadataView(decoder: decoder, style: .list)
                    } else if let loadError = loadError {
                        Text("Error loading metadata: \(loadError)")
                    } else {
                        ProgressView("Loading metadata...")
                    }
                }
                .navigationTitle("Metadata")
            }
            .task(id: filePath) {
                await loadDecoder()
            }
        }

        private func loadDecoder() async {
            await MainActor.run {
                decoder = nil
                loadError = nil
            }

            do {
                let loadedDecoder = try await DCMDecoder(contentsOfFile: filePath)
                await MainActor.run {
                    decoder = loadedDecoder
                }
            } catch {
                await MainActor.run {
                    decoder = nil
                    loadError = error.localizedDescription
                }
            }
        }
    }

    return ListMetadataView(filePath: "/path/to/image.dcm")
}

// MARK: - Modal Presentation

/// Presents a view that displays a DICOM image and lets the user open its metadata in a modal sheet.
/// 
/// The sheet contains a navigation-wrapped MetadataView for the same DICOM file and includes a Done button to dismiss it. The view is initialized with a built-in example DICOM file URL.
/// Display a DICOM image and present its metadata in a modal sheet.
/// - Returns: A view that shows a DICOM image and, when the "Show Metadata" button is tapped, presents a modal sheet containing the image's metadata wrapped in a navigation view with a Done button to dismiss.
func metadataModalSheet() -> some View {
    struct MetadataSheetView: View {
        @State private var showingMetadata = false
        @State private var metadataDecoder: DCMDecoder?
        @State private var metadataLoadError: String?
        let dicomURL: URL

        var body: some View {
            VStack {
                DicomImageView(url: dicomURL)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                Button("Show Metadata") {
                    showingMetadata = true
                }
                .buttonStyle(.borderedProminent)
                .padding()
            }
            .sheet(isPresented: $showingMetadata) {
                NavigationView {
                    Group {
                        if let metadataDecoder = metadataDecoder {
                            MetadataView(decoder: metadataDecoder)
                        } else if let metadataLoadError = metadataLoadError {
                            Text("Failed to load metadata: \(metadataLoadError)")
                        } else {
                            ProgressView("Loading metadata...")
                        }
                    }
                    .navigationTitle("Metadata")
                    .inlineNavigationBarTitle()
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") {
                                showingMetadata = false
                            }
                        }
                    }
                }
                .task(id: showingMetadata) {
                    guard showingMetadata else { return }
                    await loadMetadataForSheet()
                }
            }
        }

        private func loadMetadataForSheet() async {
            await MainActor.run {
                metadataDecoder = nil
                metadataLoadError = nil
            }

            do {
                let loadedDecoder = try await DCMDecoder(contentsOfFile: dicomURL.path)
                let isStillPresented = await MainActor.run { showingMetadata }
                guard isStillPresented else { return }
                await MainActor.run {
                    metadataDecoder = loadedDecoder
                }
            } catch {
                let isStillPresented = await MainActor.run { showingMetadata }
                guard isStillPresented else { return }
                await MainActor.run {
                    metadataDecoder = nil
                    metadataLoadError = error.localizedDescription
                }
            }
        }
    }

    return MetadataSheetView(dicomURL: URL(fileURLWithPath: "/path/to/image.dcm"))
}

/// Displays a SwiftUI example that shows a DICOM image with an Info button which presents the image's metadata in a popover.
/// 
/// The view shows a DicomImageView and an "Info" button that opens a popover containing a form-styled MetadataView loaded from a decoder created for the bundled DICOM file.
/// Creates a view that shows a DICOM image with an "Info" button which presents the file's metadata in a popover.
/// 
/// The popover displays a form-styled `MetadataView` wrapped in a `NavigationView` titled "Info" and sized to 400×600.
/// - Returns: A view containing the DICOM image and an Info button that presents the metadata popover when tapped.
func metadataPopover() -> some View {
    struct MetadataPopoverView: View {
        @State private var showingMetadata = false
        @State private var metadataDecoder: DCMDecoder?
        @State private var metadataLoadError: String?
        let dicomURL: URL

        var body: some View {
            VStack {
                DicomImageView(url: dicomURL)

                Button("Info") {
                    showingMetadata = true
                }
                .buttonStyle(.bordered)
                .padding()
                .popover(isPresented: $showingMetadata) {
                    Group {
                        if let metadataDecoder = metadataDecoder {
                            NavigationView {
                                MetadataView(decoder: metadataDecoder, style: .form)
                                    .navigationTitle("Info")
                                    .inlineNavigationBarTitle()
                            }
                            .frame(width: 400, height: 600)
                        } else if let metadataLoadError = metadataLoadError {
                            Text("Error: \(metadataLoadError)")
                                .frame(width: 400, height: 600)
                        } else {
                            ProgressView("Loading metadata...")
                                .frame(width: 400, height: 600)
                        }
                    }
                }
            }
            .task(id: showingMetadata) {
                guard showingMetadata else { return }
                await loadMetadataForPopover()
            }
        }

        private func loadMetadataForPopover() async {
            await MainActor.run {
                metadataDecoder = nil
                metadataLoadError = nil
            }

            do {
                let loadedDecoder = try await DCMDecoder(contentsOfFile: dicomURL.path)
                let isStillPresented = await MainActor.run { showingMetadata }
                guard isStillPresented else { return }
                await MainActor.run {
                    metadataDecoder = loadedDecoder
                }
            } catch {
                let isStillPresented = await MainActor.run { showingMetadata }
                guard isStillPresented else { return }
                await MainActor.run {
                    metadataDecoder = nil
                    metadataLoadError = error.localizedDescription
                }
            }
        }
    }

    return MetadataPopoverView(dicomURL: URL(fileURLWithPath: "/path/to/ct_scan.dcm"))
}

// MARK: - Integrated Viewers

/// Creates a tabbed SwiftUI view that displays a DICOM image alongside its metadata.
/// 
/// The view presents two tabs: an image viewer that loads the DICOM pixel data and a metadata viewer that initializes a decoder from the same DICOM file.
/// Creates a tabbed view that presents a DICOM image alongside its metadata.
/// 
/// The view has two tabs: an Image tab that shows a DICOM image preview and a Metadata tab that displays the file's metadata.
/// The Metadata tab is shown only if metadata can be loaded from the file URL used to initialize the view model.
/// - Returns: A SwiftUI view containing the Image and conditional Metadata tabs.
func integratedMetadataViewer() -> some View {
    struct IntegratedViewer: View {
        @StateObject private var imageVM = DicomImageViewModel()
        @State private var selectedTab = 0
        @State private var metadataDecoder: DCMDecoder?
        @State private var metadataLoadError: String?
        let dicomURL: URL

        var body: some View {
            TabView(selection: $selectedTab) {
                // Image tab
                DicomImageView(viewModel: imageVM)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.black)
                    .tabItem {
                        Label("Image", systemImage: "photo")
                    }
                    .tag(0)

                // Metadata tab
                Group {
                    if let metadataDecoder = metadataDecoder {
                        MetadataView(decoder: metadataDecoder)
                    } else if let metadataLoadError = metadataLoadError {
                        Text("Error: \(metadataLoadError)")
                    } else {
                        ProgressView("Loading metadata...")
                    }
                }
                .tabItem {
                    Label("Metadata", systemImage: "info.circle")
                }
                .tag(1)
            }
            .task(id: dicomURL) {
                await imageVM.loadImage(from: dicomURL)
                await loadMetadata()
            }
        }

        private func loadMetadata() async {
            await MainActor.run {
                metadataDecoder = nil
                metadataLoadError = nil
            }

            do {
                let loadedDecoder = try await DCMDecoder(contentsOfFile: dicomURL.path)
                await MainActor.run {
                    metadataDecoder = loadedDecoder
                }
            } catch {
                await MainActor.run {
                    metadataDecoder = nil
                    metadataLoadError = error.localizedDescription
                }
            }
        }
    }

    return IntegratedViewer(dicomURL: URL(fileURLWithPath: "/path/to/image.dcm"))
}

/// Displays a responsive split view combining a DICOM image preview and its metadata.
///
/// - On macOS, presents an HSplitView with the image on the left and form-styled metadata on the right.
/// On iOS and other platforms, uses a side-by-side HStack when the available width is greater than 600 points and a stacked VStack (image above metadata) for narrower widths.
/// - Returns: A SwiftUI view that shows a DICOM image alongside its metadata in a platform- and size-adaptive split layout.
func splitViewMetadata() -> some View {
    struct SplitViewMetadata: View {
        @StateObject private var imageVM = DicomImageViewModel()
        @State private var metadataDecoder: DCMDecoder?
        @State private var metadataLoadError: String?
        let dicomURL: URL

        var body: some View {
            #if os(macOS)
            HSplitView {
                // Left: Image
                DicomImageView(viewModel: imageVM)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                // Right: Metadata
                metadataPane(style: .form)
                    .frame(width: 350)
            }
            #else
            // iOS: Use side-by-side layout for larger screens
            GeometryReader { geometry in
                if geometry.size.width > 600 {
                    HStack(spacing: 0) {
                        DicomImageView(viewModel: imageVM)
                            .frame(width: geometry.size.width * 0.6)

                        metadataPane(style: .form)
                            .frame(width: geometry.size.width * 0.4)
                    }
                } else {
                    // Portrait: Stacked layout
                    VStack(spacing: 0) {
                        DicomImageView(viewModel: imageVM)
                            .frame(height: geometry.size.height * 0.5)

                        metadataPane(style: .list)
                            .frame(height: geometry.size.height * 0.5)
                    }
                }
            }
            #endif
            .task(id: dicomURL) {
                await imageVM.loadImage(from: dicomURL)
                await loadMetadata()
            }
        }

        @ViewBuilder
        private func metadataPane(style: MetadataView.PresentationStyle) -> some View {
            if let metadataDecoder = metadataDecoder {
                MetadataView(decoder: metadataDecoder, style: style)
            } else if let metadataLoadError = metadataLoadError {
                Text("Error: \(metadataLoadError)")
                    .multilineTextAlignment(.center)
                    .padding()
            } else {
                ProgressView("Loading metadata...")
            }
        }

        private func loadMetadata() async {
            await MainActor.run {
                metadataDecoder = nil
                metadataLoadError = nil
            }

            do {
                let loadedDecoder = try await DCMDecoder(contentsOfFile: dicomURL.path)
                await MainActor.run {
                    metadataDecoder = loadedDecoder
                }
            } catch {
                await MainActor.run {
                    metadataDecoder = nil
                    metadataLoadError = error.localizedDescription
                }
            }
        }
    }

    return SplitViewMetadata(dicomURL: URL(fileURLWithPath: "/path/to/ct_scan.dcm"))
}

// MARK: - Custom Metadata Display

/// Displays a navigation-wrapped list showing selected DICOM metadata fields (Patient, Study, Image) extracted from a local DCM file.
/// Displays selected DICOM metadata fields grouped into Patient, Study, and Image sections, loading a decoder from a bundled DCM file.
/// 
/// The view shows Patient Name and ID, Study Description and Modality, and Image Dimensions and Bit Depth. If the decoder fails to initialize from the file path, a `Text` view containing the error message is returned.
/// - Returns: A SwiftUI view presenting the extracted metadata in a navigation-wrapped list, or an error `Text` if the DCM file cannot be loaded.
func customMetadataFields() -> some View {
    struct CustomMetadataView: View {
        let decoder: DCMDecoder

        var body: some View {
            List {
                Section(header: Text("Patient")) {
                    HStack {
                        Text("Name")
                        Spacer()
                        Text(decoder.info(for: .patientName) ?? "N/A")
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Text("ID")
                        Spacer()
                        Text(decoder.info(for: .patientID) ?? "N/A")
                            .foregroundColor(.secondary)
                    }
                }

                Section(header: Text("Study")) {
                    HStack {
                        Text("Description")
                        Spacer()
                        Text(decoder.info(for: .studyDescription) ?? "N/A")
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Text("Modality")
                        Spacer()
                        Text(decoder.info(for: .modality) ?? "N/A")
                            .foregroundColor(.secondary)
                    }
                }

                Section(header: Text("Image")) {
                    HStack {
                        Text("Dimensions")
                        Spacer()
                        Text("\(decoder.width) × \(decoder.height)")
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Text("Bit Depth")
                        Spacer()
                        Text("\(decoder.bitDepth) bits")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("DICOM Info")
        }
    }

    struct AsyncCustomMetadataView: View {
        let filePath: String
        @State private var decoder: DCMDecoder?
        @State private var loadError: String?

        var body: some View {
            NavigationView {
                Group {
                    if let decoder = decoder {
                        CustomMetadataView(decoder: decoder)
                    } else if let loadError = loadError {
                        Text("Error: \(loadError)")
                    } else {
                        ProgressView("Loading metadata...")
                    }
                }
                .navigationTitle("DICOM Info")
            }
            .task(id: filePath) {
                await loadDecoder()
            }
        }

        private func loadDecoder() async {
            await MainActor.run {
                decoder = nil
                loadError = nil
            }

            do {
                let loadedDecoder = try await DCMDecoder(contentsOfFile: filePath)
                await MainActor.run {
                    decoder = loadedDecoder
                }
            } catch {
                await MainActor.run {
                    decoder = nil
                    loadError = error.localizedDescription
                }
            }
        }
    }

    return AsyncCustomMetadataView(filePath: "/path/to/image.dcm")
}

// MARK: - Searchable Metadata

/// Presents a SwiftUI example that displays DICOM metadata with a searchable interface.
/// Presents a DICOM metadata viewer that offers a searchable interface when the platform supports it.
/// - Returns: A view displaying metadata loaded from the bundled DICOM file at "/path/to/image.dcm"; if the decoder cannot be created, returns a text view describing the load error.
func searchableMetadata() -> some View {
    struct SearchableMetadataView: View {
        @State private var searchText = ""
        let decoder: DCMDecoder

        var body: some View {
            NavigationView {
                if #available(iOS 15.0, macOS 12.0, *) {
                    MetadataView(decoder: decoder)
                        .searchable(text: $searchText, prompt: "Search metadata")
                        .navigationTitle("Metadata")
                } else {
                    VStack {
                        TextField("Search", text: $searchText)
                            .textFieldStyle(.roundedBorder)
                            .padding()

                        MetadataView(decoder: decoder)
                    }
                    .navigationTitle("Metadata")
                }
            }
        }
    }

    struct AsyncSearchableMetadataView: View {
        let filePath: String
        @State private var decoder: DCMDecoder?
        @State private var loadError: String?

        var body: some View {
            Group {
                if let decoder = decoder {
                    SearchableMetadataView(decoder: decoder)
                } else if let loadError = loadError {
                    Text("Error loading metadata: \(loadError)")
                } else {
                    ProgressView("Loading metadata...")
                }
            }
            .task(id: filePath) {
                await loadDecoder()
            }
        }

        private func loadDecoder() async {
            await MainActor.run {
                decoder = nil
                loadError = nil
            }

            do {
                let loadedDecoder = try await DCMDecoder(contentsOfFile: filePath)
                await MainActor.run {
                    decoder = loadedDecoder
                }
            } catch {
                await MainActor.run {
                    decoder = nil
                    loadError = error.localizedDescription
                }
            }
        }
    }

    return AsyncSearchableMetadataView(filePath: "/path/to/image.dcm")
}

// MARK: - Export Metadata

/// Displays DICOM metadata and provides an export action that shares a generated text summary.
///
/// - A view showing the MetadataView for a DCMDecoder with a toolbar export button that presents a share sheet containing a plain-text export of patient, study, and image properties.
/// - Returns: A view presenting the metadata and an export button that opens a share sheet with the exported metadata text.
func exportableMetadata() -> some View {
    struct ExportableMetadataView: View {
        @State private var showingExportSheet = false
        @State private var decoder: DCMDecoder?
        @State private var loadError: String?
        let filePath: String

        var body: some View {
            NavigationView {
                Group {
                    if let decoder = decoder {
                        MetadataView(decoder: decoder)
                    } else if let loadError = loadError {
                        Text("Error loading metadata: \(loadError)")
                    } else {
                        ProgressView("Loading metadata...")
                    }
                }
                .navigationTitle("Metadata")
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button(action: exportMetadata) {
                            Image(systemName: "square.and.arrow.up")
                        }
                        .disabled(decoder == nil)
                    }
                }
                .sheet(isPresented: $showingExportSheet) {
                    ShareSheet(items: [generateMetadataText()])
                }
            }
            .task(id: filePath) {
                await loadDecoder()
            }
        }

        private func loadDecoder() async {
            await MainActor.run {
                decoder = nil
                loadError = nil
            }

            do {
                let loadedDecoder = try await DCMDecoder(contentsOfFile: filePath)
                await MainActor.run {
                    decoder = loadedDecoder
                }
            } catch {
                await MainActor.run {
                    decoder = nil
                    loadError = error.localizedDescription
                }
            }
        }

        /// Triggers display of the export sheet.
        /// 
        /// Triggers presentation of the export/share sheet by setting the export sheet state to `true`.
        private func exportMetadata() {
            showingExportSheet = true
        }

        /// Builds a plain-text DICOM metadata summary suitable for sharing.
        /// Builds a plain-text summary of the decoder's patient, study, and image metadata suitable for export.
        /// - Returns: A formatted string containing Patient Information, Study Information, and Image Properties; missing fields are represented as "N/A".
        private func generateMetadataText() -> String {
            guard let decoder = decoder else {
                return "No metadata loaded."
            }

            var text = "DICOM Metadata Export\n"
            text += "====================\n\n"

            text += "Patient Information:\n"
            text += "  Name: \(decoder.info(for: .patientName) ?? "N/A")\n"
            text += "  ID: \(decoder.info(for: .patientID) ?? "N/A")\n"
            text += "  Sex: \(decoder.info(for: .patientSex) ?? "N/A")\n"
            text += "  Age: \(decoder.info(for: .patientAge) ?? "N/A")\n\n"

            text += "Study Information:\n"
            text += "  Description: \(decoder.info(for: .studyDescription) ?? "N/A")\n"
            text += "  Date: \(decoder.info(for: .studyDate) ?? "N/A")\n"
            text += "  Modality: \(decoder.info(for: .modality) ?? "N/A")\n\n"

            text += "Image Properties:\n"
            text += "  Dimensions: \(decoder.width) × \(decoder.height)\n"
            text += "  Bit Depth: \(decoder.bitDepth)\n"

            return text
        }
    }

    // Simple share sheet wrapper
    #if os(iOS) || os(tvOS) || os(visionOS)
    struct ShareSheet: UIViewControllerRepresentable {
        let items: [Any]

        init(items: [Any]) {
            self.items = items
        }

        /// Create a UIActivityViewController configured with the view's activity items.
        /// - Parameters:
        ///   - context: Context provided by `UIViewControllerRepresentable` containing environment and coordinator.
        /// Creates and returns a UIActivityViewController configured with the provided activity items.
        /// - Returns: A `UIActivityViewController` initialized with `items` and no application activities.
        func makeUIViewController(context: Context) -> UIActivityViewController {
            UIActivityViewController(activityItems: items, applicationActivities: nil)
        }

        /// Updates the presented `UIActivityViewController` to reflect any changed SwiftUI state.
        /// - Parameters:
        ///   - uiViewController: The activity view controller instance managed by this representable.
        ///   - context: Contextual information about the representable's update cycle.
        /// No-op update method for the activity view controller; intentionally does not modify `uiViewController`.
        func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
    }
    #else
    struct ShareSheet: View {
        let items: [Any]

        init(items: [Any]) {
            self.items = items
        }

        var body: some View {
            Text("Sharing is unavailable on this platform.")
                .padding()
        }
    }
    #endif

    return ExportableMetadataView(filePath: "/path/to/ct_scan.dcm")
}

// MARK: - Metadata with Series Navigation

/// Demonstrates a DICOM series viewer with navigation and per-slice metadata display.
/// 
/// Shows a DicomImageView with a series navigator and a button that presents a sheet containing the metadata for the currently selected slice. The view updates the displayed image and associated metadata when the user navigates the series.
/// - Returns: A SwiftUI view configured with a sample series of slice URLs that provides image navigation and a metadata sheet for the current slice.
func metadataWithSeriesNavigation() -> some View {
    struct MetadataSeriesView: View {
        @StateObject private var navigatorVM = SeriesNavigatorViewModel()
        @StateObject private var imageVM = DicomImageViewModel()
        @State private var currentDecoder: DCMDecoder?
        @State private var showingMetadata = false
        let seriesURLs: [URL]

        var body: some View {
            VStack {
                DicomImageView(viewModel: imageVM)

                SeriesNavigatorView(
                    navigatorViewModel: navigatorVM,
                    onNavigate: { url in
                        Task {
                            await loadImageAndMetadata(url: url)
                        }
                    }
                )

                Button("Show Current Slice Metadata") {
                    showingMetadata = true
                }
                .buttonStyle(.borderedProminent)
                .padding()
                .disabled(currentDecoder == nil)
            }
            .onAppear {
                navigatorVM.setSeriesURLs(seriesURLs)
                if let firstURL = navigatorVM.currentURL {
                    Task {
                        await loadImageAndMetadata(url: firstURL)
                    }
                }
            }
            .sheet(isPresented: $showingMetadata) {
                if let decoder = currentDecoder {
                    NavigationView {
                        MetadataView(decoder: decoder)
                            .navigationTitle("Slice \(navigatorVM.currentIndex + 1) Metadata")
                            .inlineNavigationBarTitle()
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
        }

        /// Loads a DICOM decoder from the given URL, updates `currentDecoder`, and tells the image view model to load the corresponding image.
        /// Loads DICOM metadata and image from the given file URL, updates `currentDecoder`, and instructs the image view model to load the image.
        /// - Parameter url: File URL pointing to a DICOM file to load.
        private func loadImageAndMetadata(url: URL) async {
            do {
                let decoder = try await DCMDecoder(contentsOfFile: url.path)
                await MainActor.run {
                    currentDecoder = decoder
                }
                await imageVM.loadImage(decoder: decoder)
            } catch {
                print("Error loading image: \(error)")
            }
        }
    }

    let urls = (1...50).map { URL(fileURLWithPath: "/path/to/series/slice\($0).dcm") }
    return MetadataSeriesView(seriesURLs: urls)
}

// MARK: - Comparison View

/// Displays a comparison of selected metadata for two DICOM files.
/// 
/// The view lists Patient Name, Study Date, and image Dimensions for each file and highlights differences in red. If either DICOM file cannot be loaded, the function returns a view showing an error message.
/// Presents a side-by-side comparison of metadata from two DICOM files.
/// 
/// The returned view displays Patient Name, Study Date, and image Dimensions for two DICOM images and highlights any differing values in red; if loading either file fails, the view shows an error message instead.
/// - Returns: A SwiftUI `View` that either shows the comparison list (with differences highlighted) or a textual error describing the loading failure.
func compareMetadata() -> some View {
    struct CompareMetadataView: View {
        let url1: URL
        let url2: URL
        @State private var decoder1: DCMDecoder?
        @State private var decoder2: DCMDecoder?
        @State private var isLoading = true
        @State private var loadError: String?

        var body: some View {
            NavigationView {
                Group {
                    if isLoading {
                        ProgressView("Loading metadata...")
                    } else if let loadError = loadError {
                        Text("Error comparing metadata: \(loadError)")
                            .multilineTextAlignment(.center)
                            .padding()
                    } else if let decoder1 = decoder1, let decoder2 = decoder2 {
                        List {
                            Section(header: Text("Patient Name")) {
                                HStack {
                                    Text("Image 1")
                                    Spacer()
                                    Text(decoder1.info(for: .patientName) ?? "N/A")
                                        .foregroundColor(.secondary)
                                }

                                HStack {
                                    Text("Image 2")
                                    Spacer()
                                    Text(decoder2.info(for: .patientName) ?? "N/A")
                                        .foregroundColor(
                                            decoder1.info(for: .patientName) == decoder2.info(for: .patientName)
                                            ? .secondary : .red
                                        )
                                }
                            }

                            Section(header: Text("Study Date")) {
                                HStack {
                                    Text("Image 1")
                                    Spacer()
                                    Text(decoder1.info(for: .studyDate) ?? "N/A")
                                        .foregroundColor(.secondary)
                                }

                                HStack {
                                    Text("Image 2")
                                    Spacer()
                                    Text(decoder2.info(for: .studyDate) ?? "N/A")
                                        .foregroundColor(
                                            decoder1.info(for: .studyDate) == decoder2.info(for: .studyDate)
                                            ? .secondary : .red
                                        )
                                }
                            }

                            Section(header: Text("Dimensions")) {
                                HStack {
                                    Text("Image 1")
                                    Spacer()
                                    Text("\(decoder1.width) × \(decoder1.height)")
                                        .foregroundColor(.secondary)
                                }

                                HStack {
                                    Text("Image 2")
                                    Spacer()
                                    Text("\(decoder2.width) × \(decoder2.height)")
                                        .foregroundColor(
                                            decoder1.width == decoder2.width && decoder1.height == decoder2.height
                                            ? .secondary : .red
                                        )
                                }
                            }
                        }
                    } else {
                        Text("No metadata available.")
                    }
                }
                .navigationTitle("Compare Metadata")
            }
            .task(id: "\(url1.path)|\(url2.path)") {
                await loadDecoders()
            }
        }

        private func loadDecoders() async {
            await MainActor.run {
                isLoading = true
                loadError = nil
                decoder1 = nil
                decoder2 = nil
            }

            do {
                async let first = DCMDecoder(contentsOfFile: url1.path)
                async let second = DCMDecoder(contentsOfFile: url2.path)
                let (loadedDecoder1, loadedDecoder2) = try await (first, second)

                await MainActor.run {
                    decoder1 = loadedDecoder1
                    decoder2 = loadedDecoder2
                    isLoading = false
                }
            } catch {
                await MainActor.run {
                    loadError = error.localizedDescription
                    isLoading = false
                }
            }
        }
    }

    return CompareMetadataView(
        url1: URL(fileURLWithPath: "/path/to/image1.dcm"),
        url2: URL(fileURLWithPath: "/path/to/image2.dcm")
    )
}

// MARK: - Complete Metadata Application

/// Builds a sample SwiftUI view showcasing a DICOM image preview, a segmented picker to choose metadata presentation style (List or Form), and metadata sections with key information and full details, plus toolbar actions for export, copy, and print.
/// Presents a complete metadata exploration UI combining an image preview, a presentation-style picker, and metadata display with export and utility actions.
/// 
/// The view displays a DICOM image preview, lets the user choose between list and form presentation for metadata, shows key information and full metadata sections extracted from the DICOM file, and provides toolbar actions to export, copy, or print the metadata.
/// - Returns: A view that displays and lets the user interact with DICOM image and metadata (image preview, style selector, key fields, full details, and export/copy/print controls).
func completeMetadataApp() -> some View {
    struct CompleteMetadataApp: View {
        @StateObject private var imageVM = DicomImageViewModel()
        @State private var presentationStyle: MetadataView.PresentationStyle = .list
        @State private var showingExport = false
        @State private var metadataDecoder: DCMDecoder?
        @State private var metadataLoadError: String?
        let dicomURL: URL

        var body: some View {
            NavigationView {
                VStack(spacing: 0) {
                    // Image preview
                    DicomImageView(viewModel: imageVM)
                        .frame(height: 250)
                        .background(Color.black)

                    // Style picker
                    Picker("Style", selection: $presentationStyle) {
                        Text("List").tag(MetadataView.PresentationStyle.list)
                        Text("Form").tag(MetadataView.PresentationStyle.form)
                    }
                    .pickerStyle(.segmented)
                    .padding()

                    // Metadata display
                    if let metadataDecoder = metadataDecoder {
                        if presentationStyle == .form {
                            Form {
                                metadataSections(for: metadataDecoder)
                            }
                        } else {
                            List {
                                metadataSections(for: metadataDecoder)
                            }
                        }
                    } else if let metadataLoadError = metadataLoadError {
                        Text("Error loading metadata: \(metadataLoadError)")
                            .padding()
                    } else {
                        ProgressView("Loading metadata...")
                    }
                }
                .navigationTitle("DICOM Analysis")
                .toolbar {
                    ToolbarItemGroup(placement: .primaryAction) {
                        Button(action: { showingExport = true }) {
                            Image(systemName: "square.and.arrow.up")
                        }
                        .disabled(metadataDecoder == nil)

                        Menu {
                            Button(action: copyToClipboard) {
                                Label("Copy Metadata", systemImage: "doc.on.doc")
                            }

                            Button(action: printMetadata) {
                                Label("Print", systemImage: "printer")
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                    }
                }
            }
            .task(id: dicomURL) {
                await imageVM.loadImage(from: dicomURL)
                await loadMetadata()
            }
        }

        /// Builds two view sections displaying selected DICOM metadata and a full-details metadata view when available.
        /// 
        /// The first section shows key information (Patient, Study, Modality) extracted from the provided decoder; missing values are shown as "N/A". The second section attempts to load a full decoder from `dicomURL` and, if successful, embeds a `MetadataView` using the current presentation style.
        /// Builds two grouped sections: a "Key Information" section showing selected patient, study, and modality fields from the provided decoder, and an "All Details" section that attempts to load and display the full metadata using the file at `dicomURL`.
        /// - Parameter decoder: The `DCMDecoder` used to populate the "Key Information" rows.
        /// - Returns: A view containing the "Key Information" and "All Details" sections; missing fields are shown as "N/A".
        @ViewBuilder
        private func metadataSections(for decoder: DCMDecoder) -> some View {
            Section(header: Text("Key Information")) {
                HStack {
                    Text("Patient")
                    Spacer()
                    Text(decoder.info(for: .patientName) ?? "N/A")
                        .foregroundColor(.secondary)
                }

                HStack {
                    Text("Study")
                    Spacer()
                    Text(decoder.info(for: .studyDescription) ?? "N/A")
                        .foregroundColor(.secondary)
                }

                HStack {
                    Text("Modality")
                    Spacer()
                    Text(decoder.info(for: .modality) ?? "N/A")
                        .foregroundColor(.secondary)
                }
            }

            Section(header: Text("All Details")) {
                MetadataView(decoder: decoder, style: presentationStyle)
            }
        }

        private func loadMetadata() async {
            await MainActor.run {
                metadataDecoder = nil
                metadataLoadError = nil
            }

            do {
                let loadedDecoder = try await DCMDecoder(contentsOfFile: dicomURL.path)
                await MainActor.run {
                    metadataDecoder = loadedDecoder
                }
            } catch {
                await MainActor.run {
                    metadataDecoder = nil
                    metadataLoadError = error.localizedDescription
                }
            }
        }

        /// Copies the currently displayed metadata text to the system clipboard.
        ///
        /// Copies the currently displayed metadata as plain text into the system clipboard.
        private func copyToClipboard() {
            print("Copying metadata to clipboard")
            // Implement clipboard functionality
        }

        /// Initiates printing of the currently displayed DICOM metadata.
        /// 
        /// Initiates printing of the currently displayed metadata.
        /// 
        /// This is a placeholder implementation; integrate the platform print UI to produce a printable representation of the metadata.
        private func printMetadata() {
            print("Printing metadata")
            // Implement print functionality
        }
    }

    return CompleteMetadataApp(dicomURL: URL(fileURLWithPath: "/path/to/ct_scan.dcm"))
}

// MARK: - Async Metadata Loading

/// Presents a SwiftUI example view that loads DICOM metadata asynchronously and displays it when ready.
/// Loads DICOM metadata from `dicomURL` and updates the view state accordingly.
/// 
/// On success, sets `decoder` to the loaded `DCMDecoder` and sets `isLoading` to `false`. On failure, sets `error` to the thrown error and sets `isLoading` to `false`.
func asyncMetadataLoading() -> some View {
    struct AsyncMetadataView: View {
        @State private var decoder: DCMDecoder?
        @State private var isLoading = true
        @State private var error: Error?
        let dicomURL: URL

        var body: some View {
            NavigationView {
                Group {
                    if isLoading {
                        VStack(spacing: 16) {
                            ProgressView()
                            Text("Loading metadata...")
                                .foregroundColor(.secondary)
                        }
                    } else if let error = error {
                        VStack(spacing: 16) {
                            Image(systemName: "exclamationmark.triangle")
                                .font(.largeTitle)
                                .foregroundColor(.red)

                            Text("Failed to load metadata")
                                .font(.headline)

                            Text(error.localizedDescription)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .padding()
                    } else if let decoder = decoder {
                        MetadataView(decoder: decoder)
                    }
                }
                .navigationTitle("DICOM Metadata")
            }
            .task {
                await loadMetadata()
            }
        }

        /// Loads a DICOM decoder from `dicomURL` and updates the view state.
        ///
        /// Asynchronously loads DICOM metadata from `dicomURL` and updates the view state.
        /// 
        /// On success, assigns the created `DCMDecoder` to `decoder` and clears the loading flag. On failure, stores the thrown error in `error` and clears the loading flag.
        private func loadMetadata() async {
            do {
                // Simulate async loading
                let loadedDecoder = try await DCMDecoder(contentsOfFile: dicomURL.path)
                decoder = loadedDecoder
                isLoading = false
            } catch let loadError {
                error = loadError
                isLoading = false
            }
        }
    }

    return AsyncMetadataView(dicomURL: URL(fileURLWithPath: "/path/to/large_image.dcm"))
}
