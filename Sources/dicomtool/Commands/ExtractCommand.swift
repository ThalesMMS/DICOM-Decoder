//
//  ExtractCommand.swift
//
//  Command for extracting pixel data from DICOM files with windowing
//

import Foundation
import ArgumentParser
import DicomCore

// MARK: - ArgumentParser Conformance Extensions

extension ImageFormat: ExpressibleByArgument {}

extension ProcessingMode: ExpressibleByArgument {
    public init?(argument: String) {
        switch argument.lowercased() {
        case "vdsp":
            self = .vdsp
        case "metal":
            self = .metal
        case "auto":
            self = .auto
        default:
            return nil
        }
    }
}

extension MedicalPreset: ExpressibleByArgument {
    public init?(argument: String) {
        // Try to find matching case by display name
        let normalized = argument.lowercased().replacingOccurrences(of: " ", with: "")

        for preset in MedicalPreset.allCases {
            let presetName = preset.displayName.lowercased().replacingOccurrences(of: " ", with: "")
            if normalized == presetName {
                self = preset
                return
            }
        }

        return nil
    }
}

// MARK: - Extract Command

/// Extracts pixel data from DICOM files with windowing and exports to image formats.
///
/// ## Overview
///
/// ``ExtractCommand`` loads a DICOM file, applies window/level transformations for medical image
/// display, and exports the result to standard image formats (PNG or TIFF). Supports both
/// medical presets (lung, bone, brain, etc.) and custom windowing parameters.
///
/// ## Usage
///
/// Extract with lung preset:
///
/// ```bash
/// dicomtool extract image.dcm --output lung.png --preset lung
/// ```
///
/// Extract with custom windowing:
///
/// ```bash
/// dicomtool extract image.dcm --output custom.png --window-center 50 --window-width 400
/// ```
///
/// Extract to TIFF format with GPU acceleration:
///
/// ```bash
/// dicomtool extract image.dcm --output image.tiff --format tiff --processing-mode metal
/// ```
///
/// Extract with automatic optimal windowing:
///
/// ```bash
/// dicomtool extract image.dcm --output auto.png
/// ```
///
/// ## Topics
///
/// ### Command Execution
///
/// - ``run()``
///
/// ### Windowing Options
///
/// The command supports three windowing modes (mutually exclusive):
/// 1. **Preset windowing**: Use `--preset` with a medical preset name
/// 2. **Custom windowing**: Use `--window-center` and `--window-width` together
/// 3. **Automatic windowing**: No windowing flags (calculates optimal values from image data)
struct ExtractCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "extract",
        abstract: "Extract and export DICOM pixel data with windowing",
        discussion: """
            Loads a DICOM file, applies window/level transformations, and exports to PNG or TIFF.

            Windowing Options (choose one):
            • Preset: --preset lung|bone|brain|softtissue|liver|mediastinum|abdomen|spine|pelvis|angiography|pulmonaryembolism|mammography|petscan
            • Custom: --window-center <value> --window-width <value>
            • Automatic: No windowing flags (calculates optimal values)

            Processing modes (--processing-mode):
            • vdsp: CPU acceleration (best for <800×800 images)
            • metal: GPU acceleration (best for ≥800×800 images)
            • auto: Automatic selection (default)

            Examples:
              dicomtool extract ct.dcm --output lung.png --preset lung
              dicomtool extract ct.dcm --output custom.png --window-center 50 --window-width 400
              dicomtool extract ct.dcm --output auto.png --processing-mode metal
            """
    )

    // MARK: - Arguments

    @Argument(
        help: "Path to the DICOM file to extract",
        completion: .file(extensions: ["dcm", "dicom"])
    )
    var file: String

    // MARK: - Required Options

    @Option(
        name: [.short, .long],
        help: "Output file path (PNG or TIFF)",
        completion: .file(extensions: ["png", "tiff"])
    )
    var output: String

    // MARK: - Export Options

    @Option(
        name: [.short, .long],
        help: "Output format: png or tiff (default: png)"
    )
    var format: ImageFormat = .png

    @Flag(
        name: .long,
        help: "Overwrite output file if it exists"
    )
    var overwrite: Bool = false

    // MARK: - Windowing Options

    @Option(
        name: .long,
        help: "Medical windowing preset (lung, bone, brain, softtissue, liver, mediastinum, abdomen, spine, pelvis, angiography, pulmonaryembolism, mammography, petscan)"
    )
    var preset: MedicalPreset?

    @Option(
        name: .long,
        help: "Custom window center value (use with --window-width)"
    )
    var windowCenter: Double?

    @Option(
        name: .long,
        help: "Custom window width value (use with --window-center)"
    )
    var windowWidth: Double?

    // MARK: - Processing Options

    @Option(
        name: .long,
        help: "Processing mode: vdsp (CPU), metal (GPU), or auto (default: auto)"
    )
    var processingMode: ProcessingMode = .auto

    // MARK: - Execution

    mutating func run() throws {
        // Validate file path
        let fileURL = URL(fileURLWithPath: file)
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw CLIError.fileNotReadable(
                path: file,
                reason: "File does not exist"
            )
        }

        // Validate windowing options
        try validateWindowingOptions()

        // Load DICOM file
        let decoder: DCMDecoder
        do {
            decoder = try DCMDecoder(contentsOf: fileURL)
        } catch {
            throw CLIError.invalidDICOMFile(
                path: file,
                reason: error.localizedDescription
            )
        }

        // Get 16-bit pixel data
        guard let pixels16 = decoder.getPixels16() else {
            throw CLIError.outputGenerationFailed(
                operation: "pixel extraction",
                reason: "No 16-bit pixel data available in file"
            )
        }

        // Determine windowing parameters
        let windowSettings: WindowSettings
        if let preset = preset {
            windowSettings = DCMWindowingProcessor.getPresetValuesV2(preset: preset)
        } else if let center = windowCenter, let width = windowWidth {
            windowSettings = WindowSettings(center: center, width: width)
        } else {
            // Calculate optimal windowing automatically
            windowSettings = DCMWindowingProcessor.calculateOptimalWindowLevelV2(pixels16: pixels16)
        }

        // Verify window settings are valid
        guard windowSettings.isValid else {
            throw CLIError.outputGenerationFailed(
                operation: "windowing",
                reason: "Invalid window settings: center=\(windowSettings.center), width=\(windowSettings.width)"
            )
        }

        // Apply windowing
        guard let pixels8Data = DCMWindowingProcessor.applyWindowLevel(
            pixels16: pixels16,
            center: windowSettings.center,
            width: windowSettings.width,
            processingMode: processingMode
        ) else {
            throw CLIError.outputGenerationFailed(
                operation: "windowing",
                reason: "Failed to apply window/level transformation"
            )
        }

        // Convert Data to [UInt8]
        let pixels8 = [UInt8](pixels8Data)

        // Export to image file
        let outputURL = URL(fileURLWithPath: output)
        let exporter = ImageExporter()
        let exportOptions = ExportOptions(
            format: format,
            quality: 1.0,
            overwrite: overwrite
        )

        try exporter.export(
            pixels: pixels8,
            width: decoder.width,
            height: decoder.height,
            to: outputURL,
            options: exportOptions
        )

        // Print success message
        let windowInfo: String
        if let preset = preset {
            windowInfo = "preset=\(preset.displayName)"
        } else if windowCenter != nil {
            windowInfo = "center=\(String(format: "%.1f", windowSettings.center)), width=\(String(format: "%.1f", windowSettings.width))"
        } else {
            windowInfo = "auto (center=\(String(format: "%.1f", windowSettings.center)), width=\(String(format: "%.1f", windowSettings.width)))"
        }

        print("✓ Extracted \(decoder.width)×\(decoder.height) image to \(outputURL.lastPathComponent)")
        print("  Windowing: \(windowInfo)")
        print("  Processing: \(processingModeDescription())")
        print("  Format: \(format.description)")
    }

    // MARK: - Validation

    /// Validates that windowing options are used correctly.
    private func validateWindowingOptions() throws {
        // Check for conflicting options
        let hasPreset = preset != nil
        let hasCustomCenter = windowCenter != nil
        let hasCustomWidth = windowWidth != nil

        // Preset and custom windowing are mutually exclusive
        if hasPreset && (hasCustomCenter || hasCustomWidth) {
            throw CLIError.invalidArgument(
                argument: "--preset / --window-center / --window-width",
                value: "",
                reason: "Cannot use --preset with --window-center/--window-width. Choose one windowing method."
            )
        }

        // If one custom windowing parameter is specified, both must be
        if hasCustomCenter != hasCustomWidth {
            throw CLIError.invalidArgument(
                argument: hasCustomCenter ? "--window-center" : "--window-width",
                value: "",
                reason: "Both --window-center and --window-width must be specified together for custom windowing"
            )
        }

        // Validate custom windowing values
        if let width = windowWidth, width <= 0 {
            throw CLIError.invalidArgument(
                argument: "--window-width",
                value: String(width),
                reason: "Window width must be positive"
            )
        }
    }

    /// Returns a human-readable description of the processing mode.
    private func processingModeDescription() -> String {
        switch processingMode {
        case .vdsp:
            return "vDSP (CPU)"
        case .metal:
            return "Metal (GPU)"
        case .auto:
            return "Auto (vDSP or Metal based on image size)"
        }
    }
}
