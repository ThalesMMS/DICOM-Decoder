//
//  DocumentPickerService.swift
//
//  Service for handling DICOM file and folder selection
//
//  This service provides reusable document picker functionality for selecting
//  DICOM files and folders throughout the app. It wraps UIDocumentPickerViewController
//  in a SwiftUI-compatible interface with support for single/multiple selection
//  and directory picking.
//
//  Platform Availability:
//
//  iOS 13+ - Built with SwiftUI and UIKit's UIDocumentPickerViewController.
//

import SwiftUI
#if os(iOS)
import UIKit
#endif

// MARK: - Document Picker Configuration

/// Configuration options for document picker behavior.
public struct DocumentPickerConfiguration {
    /// Whether to allow selecting multiple files
    public let allowsMultipleSelection: Bool

    /// Whether to allow selecting directories
    public let allowsDirectories: Bool

    /// Document types to allow (UTI strings)
    public let documentTypes: [String]

    /// Creates a configuration for DICOM file selection
    /// - Parameters:
    ///   - allowsMultipleSelection: Whether multiple files can be selected. Default is false.
    ///   - allowsDirectories: Whether directories can be selected. Default is false.
    public init(
        allowsMultipleSelection: Bool = false,
        allowsDirectories: Bool = false
    ) {
        self.allowsMultipleSelection = allowsMultipleSelection
        self.allowsDirectories = allowsDirectories

        // DICOM file types and broad fallback that includes .dcm files
        var types = ["org.nema.dicom", "public.data"]

        // Add folder support if needed
        if allowsDirectories {
            types.append("public.folder")
        }

        self.documentTypes = types
    }

    /// Preset configuration for single DICOM file selection
    public static let singleFile = DocumentPickerConfiguration(
        allowsMultipleSelection: false,
        allowsDirectories: false
    )

    /// Preset configuration for multiple DICOM file selection
    public static let multipleFiles = DocumentPickerConfiguration(
        allowsMultipleSelection: true,
        allowsDirectories: false
    )

    /// Preset configuration for directory selection (for series/studies)
    public static let directory = DocumentPickerConfiguration(
        allowsMultipleSelection: false,
        allowsDirectories: true
    )

    /// Preset configuration for multiple files and directories
    public static let mixed = DocumentPickerConfiguration(
        allowsMultipleSelection: true,
        allowsDirectories: true
    )
}

// MARK: - Document Picker Service

#if os(iOS)
/// SwiftUI wrapper for UIDocumentPickerViewController for DICOM file selection.
///
/// Provides a reusable interface for presenting document pickers with configurable
/// behavior for single/multiple selection and directory picking.
///
/// Example usage:
/// ```swift
/// @State private var showPicker = false
///
/// var body: some View {
///     Button("Select DICOM") {
///         showPicker = true
///     }
///     .sheet(isPresented: $showPicker) {
///         DocumentPickerView(configuration: .singleFile) { urls in
///             // Handle selected URLs
///             if let url = urls.first {
///                 processFile(url)
///             }
///         }
///     }
/// }
/// ```
public struct DocumentPickerView: UIViewControllerRepresentable {

    // MARK: - Properties

    /// Configuration for picker behavior
    private let configuration: DocumentPickerConfiguration

    /// Callback invoked when files are selected
    private let onPick: ([URL]) -> Void

    /// Callback invoked when picker is cancelled
    private let onCancel: (() -> Void)?

    // MARK: - Initialization

    /// Creates a document picker view.
    /// - Parameters:
    ///   - configuration: Configuration for picker behavior. Default is `.singleFile`.
    ///   - onPick: Callback invoked with selected URLs when user picks files.
    ///   - onCancel: Optional callback invoked when user cancels. Default is nil.
    public init(
        configuration: DocumentPickerConfiguration = .singleFile,
        onPick: @escaping ([URL]) -> Void,
        onCancel: (() -> Void)? = nil
    ) {
        self.configuration = configuration
        self.onPick = onPick
        self.onCancel = onCancel
    }

    /// Convenience initializer for single file selection.
    /// - Parameters:
    ///   - onPick: Callback invoked with selected URL when user picks a file.
    ///   - onCancel: Optional callback invoked when user cancels. Default is nil.
    public init(
        onPick: @escaping (URL) -> Void,
        onCancel: (() -> Void)? = nil
    ) {
        self.configuration = .singleFile
        self.onPick = { urls in
            if let url = urls.first {
                onPick(url)
            }
        }
        self.onCancel = onCancel
    }

    // MARK: - UIViewControllerRepresentable

    public func makeCoordinator() -> Coordinator {
        Coordinator(onPick: onPick, onCancel: onCancel)
    }

    public func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(
            documentTypes: configuration.documentTypes,
            in: .import
        )
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = configuration.allowsMultipleSelection
        picker.shouldShowFileExtensions = true

        return picker
    }

    public func updateUIViewController(
        _ uiViewController: UIDocumentPickerViewController,
        context: Context
    ) {
        // No updates needed
    }

    // MARK: - Coordinator

    /// Coordinator handling document picker delegate callbacks.
    public final class Coordinator: NSObject, UIDocumentPickerDelegate {
        private let onPick: ([URL]) -> Void
        private let onCancel: (() -> Void)?

        init(onPick: @escaping ([URL]) -> Void, onCancel: (() -> Void)?) {
            self.onPick = onPick
            self.onCancel = onCancel
        }

        public func documentPicker(
            _ controller: UIDocumentPickerViewController,
            didPickDocumentsAt urls: [URL]
        ) {
            onPick(urls)
        }

        public func documentPickerWasCancelled(
            _ controller: UIDocumentPickerViewController
        ) {
            onCancel?()
        }
    }
}
#endif

// MARK: - macOS Support

#if os(macOS)
/// Placeholder for macOS document picker functionality.
///
/// macOS uses NSOpenPanel instead of UIDocumentPickerViewController.
/// This can be implemented in a future update if macOS support is needed.
public struct DocumentPickerView: View {
    private let onPick: ([URL]) -> Void

    public init(
        configuration: DocumentPickerConfiguration = .singleFile,
        onPick: @escaping ([URL]) -> Void,
        onCancel: (() -> Void)? = nil
    ) {
        self.onPick = onPick
    }

    public init(
        onPick: @escaping (URL) -> Void,
        onCancel: (() -> Void)? = nil
    ) {
        self.onPick = { urls in
            if let url = urls.first {
                onPick(url)
            }
        }
    }

    public var body: some View {
        Text("Document picker not yet implemented for macOS")
            .foregroundColor(.secondary)
    }
}
#endif

// MARK: - Previews

#if DEBUG
struct DocumentPickerView_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 20) {
            Text("Document Picker Examples")
                .font(.title)

            Button("Single File Picker") {
                // Preview only - no actual functionality
            }

            Button("Multiple Files Picker") {
                // Preview only - no actual functionality
            }

            Button("Directory Picker") {
                // Preview only - no actual functionality
            }
        }
        .padding()
    }
}
#endif
