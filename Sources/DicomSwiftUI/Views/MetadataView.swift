//
//  MetadataView.swift
//
//  SwiftUI view for displaying DICOM metadata in a formatted list
//
//  This view provides a structured display of DICOM metadata tags organized
//  into logical sections (Patient, Study, Series, Image Properties). It uses
//  native SwiftUI components for optimal platform integration and automatically
//  formats DICOM values for human readability.
//
//  The view supports both List and Form presentation styles, making it suitable
//  for modal sheets, detail panels, or inline embedding. All metadata fields
//  include proper labels and accessibility support for VoiceOver.
//
//  Platform Availability:
//
//  Available on iOS 13+, macOS 12+, and all platforms supporting SwiftUI.
//  Uses native SwiftUI components for optimal performance and platform integration.
//
//  Accessibility:
//
//  All metadata fields include proper accessibility labels and values for
//  VoiceOver support. Section headers are marked with appropriate traits.
//

import SwiftUI
import DicomCore

/// A SwiftUI view for displaying DICOM metadata.
///
/// ## Overview
///
/// ``MetadataView`` provides a formatted display of DICOM metadata tags organized
/// into logical sections. It extracts and displays patient information, study details,
/// series information, and image properties from a ``DicomDecoderProtocol`` instance.
///
/// The view automatically handles missing or empty metadata fields by displaying
/// "N/A" placeholders. It supports both `.list` and `.form` presentation styles,
/// allowing seamless integration into different UI contexts.
///
/// **Key Features:**
/// - Organized metadata sections (Patient, Study, Series, Image)
/// - Automatic formatting of DICOM values
/// - Support for List and Form styles
/// - Dark mode support
/// - Full accessibility support for VoiceOver
/// - Handles missing metadata gracefully
///
/// **Displayed Metadata:**
/// - **Patient:** Name, ID, Sex, Age
/// - **Study:** Description, Date, Time, ID, Modality
/// - **Series:** Description, Number, Instance Count
/// - **Image:** Dimensions, Pixel Spacing, Bits, Window/Level
///
/// ## Usage
///
/// Display metadata in a List:
///
/// ```swift
/// struct ContentView: View {
///     let decoder: DCMDecoder
///
///     var body: some View {
///         MetadataView(decoder: decoder)
///     }
/// }
/// ```
///
/// Use Form style for settings-like appearance:
///
/// ```swift
/// MetadataView(decoder: decoder, style: .form)
///     .navigationTitle("DICOM Metadata")
/// ```
///
/// Embed in a modal sheet:
///
/// ```swift
/// struct DicomViewer: View {
///     @State private var showingMetadata = false
///     let decoder: DCMDecoder
///
///     var body: some View {
///         VStack {
///             DicomImageView(decoder: decoder)
///
///             Button("Show Metadata") {
///                 showingMetadata = true
///             }
///         }
///         .sheet(isPresented: $showingMetadata) {
///             NavigationView {
///                 MetadataView(decoder: decoder)
///                     .navigationTitle("Metadata")
///                     .inlineNavigationBarTitle()
///                     .toolbar {
///                         ToolbarItem(placement: .confirmationAction) {
///                             Button("Done") {
///                                 showingMetadata = false
///                             }
///                         }
///                     }
///             }
///         }
///     }
/// }
/// ```
///
/// Access specific sections:
///
/// ```swift
/// // Display only patient and study info
/// List {
///     Section(header: Text("Patient Information")) {
///         MetadataRow(label: "Name", value: decoder.info(for: .patientName))
///         MetadataRow(label: "ID", value: decoder.info(for: .patientID))
///     }
///
///     Section(header: Text("Study Information")) {
///         MetadataRow(label: "Description", value: decoder.info(for: .studyDescription))
///         MetadataRow(label: "Date", value: decoder.info(for: .studyDate))
///     }
/// }
/// ```
///
/// ## Topics
///
/// ### Creating a View
///
/// - ``init(decoder:style:)``
///
/// ### Presentation Styles
///
/// - ``PresentationStyle``
///
/// ### Customization
///
/// Apply standard SwiftUI modifiers:
/// - `.navigationTitle()` - Add title in navigation context
/// - `.navigationBarTitleDisplayMode()` - Configure title display
/// - `.toolbar()` - Add toolbar items
/// - `.background()` - Customize background color
///
@available(iOS 13.0, macOS 12.0, *)
public struct MetadataView: View {

    // MARK: - Presentation Style

    /// Presentation style for the metadata view.
    ///
    /// Controls the visual presentation of metadata sections. Both styles display
    /// the same metadata content but with different visual styling appropriate for
    /// their context.
    ///
    /// ## Usage
    ///
    /// ```swift
    /// // List style for browsing
    /// MetadataView(decoder: decoder, style: .list)
    ///
    /// // Form style for detail sheets
    /// MetadataView(decoder: decoder, style: .form)
    ///     .navigationTitle("Details")
    /// ```
    public enum PresentationStyle {
        /// Display in a standard List (scrollable, platform-native).
        ///
        /// Uses SwiftUI's `List` container with platform-native styling. Best for
        /// primary content views where metadata is the main focus. Provides standard
        /// list appearance with section headers and separators.
        case list

        /// Display in a Form (grouped style, better for settings/details).
        ///
        /// Uses SwiftUI's `Form` container with grouped styling. Best for modal sheets,
        /// detail panels, or settings-like interfaces. Provides inset grouped appearance
        /// on iOS and standard form styling on macOS.
        case form
    }

    // MARK: - Properties

    /// DICOM decoder containing metadata
    private let decoder: any DicomDecoderProtocol

    /// Presentation style for the view
    private let style: PresentationStyle

    // MARK: - Initializers

    /// Creates a metadata view from a DICOM decoder.
    ///
    /// Displays formatted DICOM metadata organized into logical sections. The view
    /// automatically extracts patient, study, series, and image information from
    /// the decoder and presents it in a readable format.
    ///
    /// - Parameters:
    ///   - decoder: An initialized ``DicomDecoderProtocol`` with loaded DICOM file
    ///   - style: Presentation style (`.list` or `.form`). Defaults to `.list`
    ///
    /// ## Example
    ///
    /// ```swift
    /// struct MetadataScreen: View {
    ///     @State private var decoder: (any DicomDecoderProtocol)?
    ///     @State private var loadError: String?
    ///     let url: URL
    ///
    ///     var body: some View {
    ///         Group {
    ///             if let decoder = decoder {
    ///                 MetadataView(decoder: decoder, style: .form)
    ///                     .navigationTitle("DICOM Info")
    ///             } else if let loadError = loadError {
    ///                 Text("Failed to load metadata: \(loadError)")
    ///             } else {
    ///                 ProgressView("Loading metadata...")
    ///             }
    ///         }
    ///         .task(id: url) {
    ///             await loadDecoder()
    ///         }
    ///     }
    ///
    ///     private func loadDecoder() async {
    ///         do {
    ///             let loadedDecoder = try await DCMDecoder(contentsOfFile: url.path)
    ///             await MainActor.run {
    ///                 decoder = loadedDecoder
    ///                 loadError = nil
    ///             }
    ///         } catch {
    ///             await MainActor.run {
    ///                 decoder = nil
    ///                 loadError = error.localizedDescription
    ///             }
    ///         }
    ///     }
    /// }
    /// ```
    ///
    public init(decoder: any DicomDecoderProtocol, style: PresentationStyle = .list) {
        self.decoder = decoder
        self.style = style
    }

    // MARK: - Body

    public var body: some View {
        Group {
            if style == .form {
                Form {
                    metadataSections
                }
            } else {
                List {
                    metadataSections
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("DICOM Metadata")
    }

    // MARK: - Metadata Sections

    /// All metadata sections organized by category.
    ///
    /// Combines all four metadata sections (Patient, Study, Series, Image Properties)
    /// into a single view builder. Sections are displayed in a logical hierarchy
    /// from patient-level information down to image-specific properties.
    @ViewBuilder
    private var metadataSections: some View {
        patientSection
        studySection
        seriesSection
        imageSection
    }

    // MARK: - Patient Information Section

    /// Patient information section.
    ///
    /// Displays patient demographics including name, ID, sex, and age. Values are
    /// extracted from DICOM tags in the Patient IE (Information Entity). Missing
    /// values display as "N/A".
    private var patientSection: some View {
        Section(header: Text("Patient Information")
            .accessibilityAddTraits(.isHeader)) {

            MetadataRow(
                label: "Name",
                value: decoder.info(for: .patientName),
                icon: "person.fill"
            )

            MetadataRow(
                label: "Patient ID",
                value: decoder.info(for: .patientID),
                icon: "number"
            )

            MetadataRow(
                label: "Sex",
                value: formatSex(decoder.info(for: .patientSex)),
                icon: "person.crop.circle"
            )

            MetadataRow(
                label: "Age",
                value: decoder.info(for: .patientAge),
                icon: "calendar"
            )
        }
    }

    // MARK: - Study Information Section

    /// Study information section.
    ///
    /// Displays study-level metadata including description, date/time, study ID,
    /// modality, and institution. Values are extracted from DICOM tags in the
    /// Study IE. Dates and times are formatted for readability.
    private var studySection: some View {
        Section(header: Text("Study Information")
            .accessibilityAddTraits(.isHeader)) {

            MetadataRow(
                label: "Description",
                value: decoder.info(for: .studyDescription),
                icon: "doc.text.fill"
            )

            MetadataRow(
                label: "Study Date",
                value: formatDate(decoder.info(for: .studyDate)),
                icon: "calendar"
            )

            MetadataRow(
                label: "Study Time",
                value: formatTime(decoder.info(for: .studyTime)),
                icon: "clock.fill"
            )

            MetadataRow(
                label: "Study ID",
                value: decoder.info(for: .studyID),
                icon: "number"
            )

            MetadataRow(
                label: "Modality",
                value: formatModality(decoder.info(for: .modality)),
                icon: "cross.case.fill"
            )

            MetadataRow(
                label: "Institution",
                value: decoder.info(for: .institutionName),
                icon: "building.2.fill"
            )
        }
    }

    // MARK: - Series Information Section

    /// Series information section.
    ///
    /// Displays series-level metadata including description, series number, instance
    /// number, and total instances in the series. Values are extracted from DICOM
    /// tags in the Series IE.
    private var seriesSection: some View {
        Section(header: Text("Series Information")
            .accessibilityAddTraits(.isHeader)) {

            MetadataRow(
                label: "Description",
                value: decoder.info(for: .seriesDescription),
                icon: "square.stack.3d.up.fill"
            )

            MetadataRow(
                label: "Series Number",
                value: decoder.info(for: .seriesNumber),
                icon: "number"
            )

            MetadataRow(
                label: "Instance Number",
                value: decoder.info(for: .instanceNumber),
                icon: "number.square.fill"
            )

            MetadataRow(
                label: "Instances in Series",
                value: decoder.info(for: .numberOfSeriesRelatedInstances),
                icon: "square.stack.fill"
            )
        }
    }

    // MARK: - Image Properties Section

    /// Image properties section.
    ///
    /// Displays image-specific technical properties including dimensions, pixel spacing,
    /// slice thickness, bit depth, photometric interpretation, and window/level settings.
    /// Values are extracted from DICOM tags in the Image IE and formatted for display.
    private var imageSection: some View {
        Section(header: Text("Image Properties")
            .accessibilityAddTraits(.isHeader)) {

            MetadataRow(
                label: "Dimensions",
                value: formatDimensions(width: decoder.width, height: decoder.height),
                icon: "arrow.up.left.and.arrow.down.right"
            )

            MetadataRow(
                label: "Pixel Spacing",
                value: formatPixelSpacing(decoder.pixelSpacingV2),
                icon: "ruler.fill"
            )

            MetadataRow(
                label: "Slice Thickness",
                value: formatMeasurement(decoder.info(for: .sliceThickness), unit: "mm"),
                icon: "square.split.2x1.fill"
            )

            MetadataRow(
                label: "Bits Allocated",
                value: decoder.info(for: .bitsAllocated),
                icon: "scalemass.fill"
            )

            MetadataRow(
                label: "Photometric",
                value: decoder.info(for: .photometricInterpretation),
                icon: "photo.fill"
            )

            MetadataRow(
                label: "Window Center",
                value: formatWindowValue(
                    decoder.windowSettingsV2.center,
                    isValid: decoder.windowSettingsV2.isValid
                ),
                icon: "slider.horizontal.3"
            )

            MetadataRow(
                label: "Window Width",
                value: formatWindowValue(
                    decoder.windowSettingsV2.width,
                    isValid: decoder.windowSettingsV2.isValid
                ),
                icon: "slider.horizontal.3"
            )
        }
    }

    // MARK: - Formatting Helpers

    /// Formats sex value for display.
    ///
    /// Converts DICOM sex codes (M/F/O) to human-readable strings (Male/Female/Other).
    /// Returns "N/A" for missing or empty values.
    ///
    /// - Parameter value: Raw DICOM sex value (typically "M", "F", or "O")
    /// Maps a DICOM patient sex code to a human-readable label.
    /// - Parameter value: The DICOM sex code string (e.g., "M", "F", "O"), may be `nil` or empty.
    /// Format a DICOM patient sex code into a human-readable label.
    /// - Parameter value: The patient sex code from DICOM (e.g., "M", "F", "O").
    /// - Returns: `"Male"` for `"M"`, `"Female"` for `"F"`, `"Other"` for `"O"`; the original value if unrecognized; `"N/A"` if `value` is `nil` or empty.
    private func formatSex(_ value: String?) -> String {
        guard let value = value, !value.isEmpty else { return "N/A" }
        switch value.uppercased() {
        case "M": return "Male"
        case "F": return "Female"
        case "O": return "Other"
        default: return value
        }
    }

    /// Formats modality value for display.
    ///
    /// Returns the raw DICOM modality code (CT, MR, XR, etc.) for display.
    /// Returns "N/A" for missing or empty values.
    ///
    /// - Parameter value: Raw DICOM modality value
    /// Provides the DICOM modality code (e.g., "CT", "MR") or a fallback when missing.
    /// - Parameter value: The modality string from DICOM metadata.
    /// Format a DICOM modality value for display, returning a human-readable fallback when missing.
    /// - Parameters:
    ///   - value: A DICOM modality code (for example, "CT", "MR", "XR"), or `nil`.
    /// - Returns: The original modality string if it is non-empty; otherwise `"N/A"`.
    private func formatModality(_ value: String?) -> String {
        guard let value = value, !value.isEmpty else { return "N/A" }
        // Return the raw modality value (CT, MR, XR, etc.)
        return value
    }

    /// Formats DICOM date (YYYYMMDD) to readable format.
    ///
    /// Converts DICOM date strings in YYYYMMDD format to ISO-style YYYY-MM-DD format.
    /// Returns the original value or "N/A" if the input is invalid or missing.
    ///
    /// - Parameter value: DICOM date string (e.g., "20240215")
    /// Formats a DICOM date string into `YYYY-MM-DD`.
    /// - Parameter value: A date string expected in `YYYYMMDD` form; may be `nil` or shorter than eight characters.
    /// Format a DICOM date string into `YYYY-MM-DD`.
    /// - Parameter value: An optional DICOM date string expected in `YYYYMMDD` format.
    /// - Returns: The date formatted as `YYYY-MM-DD` when `value` has at least 8 characters; the original `value` if it is present but shorter than 8 characters; `"N/A"` if `value` is `nil`.
    private func formatDate(_ value: String?) -> String {
        guard let value = value, value.count >= 8 else { return value ?? "N/A" }

        let year = String(value.prefix(4))
        let month = String(value.dropFirst(4).prefix(2))
        let day = String(value.dropFirst(6).prefix(2))

        return "\(year)-\(month)-\(day)"
    }

    /// Formats DICOM time (HHMMSS.FFFFFF) to readable format.
    ///
    /// Converts DICOM time strings in HHMMSS format to HH:MM:SS format. Fractional
    /// seconds are ignored. Returns the original value or "N/A" if the input is
    /// invalid or missing.
    ///
    /// - Parameter value: DICOM time string (e.g., "143025.123456")
    /// Formats a DICOM time value into `HH:MM:SS`.
    /// - Parameter value: A DICOM time string expected in the form `HHMMSS` or `HHMMSS.FFFFFF`; may be `nil`.
    /// Format a DICOM time string into `HH:MM:SS`.
    /// - Parameter value: A DICOM time value (expected in `HHMMSS` or `HHMMSS[.fractions]` form).
    /// - Returns: The time as `HH:MM:SS` when `value` contains at least six characters, the original `value` if it is shorter than six characters, or `"N/A"` if `value` is `nil`.
    private func formatTime(_ value: String?) -> String {
        guard let value = value, value.count >= 6 else { return value ?? "N/A" }

        let hour = String(value.prefix(2))
        let minute = String(value.dropFirst(2).prefix(2))
        let second = String(value.dropFirst(4).prefix(2))

        return "\(hour):\(minute):\(second)"
    }

    /// Formats image dimensions.
    ///
    /// Creates a human-readable string showing image width and height in pixels.
    ///
    /// - Parameters:
    ///   - width: Image width in pixels
    ///   - height: Image height in pixels
    /// Formats image pixel dimensions into a human-readable string.
    /// Format image dimensions into a human-readable pixel size string.
    /// - Returns: A string in the form "width × height pixels", where `width` and `height` are the provided integers.
    private func formatDimensions(width: Int, height: Int) -> String {
        return "\(width) × \(height) pixels"
    }

    /// Formats pixel spacing from V2 value type.
    ///
    /// Creates a human-readable string showing pixel spacing in millimeters. Displays
    /// 2D spacing (X × Y) or 3D spacing (X × Y × Z) depending on whether Z spacing
    /// is present. Returns "N/A" if spacing is invalid.
    ///
    /// - Parameter spacing: Pixel spacing value type
    /// Formats a PixelSpacing value into a human-readable millimeter string.
    /// - Parameter spacing: The pixel spacing containing x, y, and optional z components.
    /// Formats pixel spacing into a human-readable string in millimeters or returns `"N/A"` if the spacing is invalid.
    /// - Parameters:
    ///   - spacing: A `PixelSpacing` value containing X, Y, and optional Z spacing (in millimeters) and a validity flag.
    /// - Returns: `"N/A"` if `spacing` is not valid; otherwise a string like `"X.XX × Y.YY mm"` or `"X.XX × Y.YY × Z.ZZ mm"`.
    private func formatPixelSpacing(_ spacing: PixelSpacing) -> String {
        guard spacing.isValid else { return "N/A" }

        if spacing.z > 0 {
            return String(format: "%.2f × %.2f × %.2f mm", spacing.x, spacing.y, spacing.z)
        } else {
            return String(format: "%.2f × %.2f mm", spacing.x, spacing.y)
        }
    }

    /// Formats a measurement with unit.
    ///
    /// Appends a unit label to a numeric value string. Returns "N/A" if the value
    /// is missing or empty.
    ///
    /// - Parameters:
    ///   - value: Numeric value string
    ///   - unit: Unit label (e.g., "mm", "cm", "kg")
    /// Formats a numeric measurement string by appending a unit or returns "N/A" when the value is missing.
    /// - Parameters:
    ///   - value: The measurement value as a string; treated as missing when `nil` or empty.
    ///   - unit: The unit label to append (for example, "mm").
    /// Formats a measurement by appending the provided unit or returns a placeholder if the value is missing.
    /// - Parameters:
    ///   - value: The measurement value as a string; may be `nil` or empty.
    ///   - unit: The unit label to append to the value (e.g., "mm").
    /// - Returns: The formatted string "`<value> <unit>`" when `value` is present and not empty, otherwise `"N/A"`.
    private func formatMeasurement(_ value: String?, unit: String) -> String {
        guard let value = value, !value.isEmpty else { return "N/A" }
        return "\(value) \(unit)"
    }

    /// Formats window/level values.
    ///
    /// Converts window center and width Double values to formatted strings with
    /// one decimal place precision.
    ///
    /// - Parameters:
    ///   - value: Window center or width value
    ///   - isValid: Whether the current window settings are valid.
    /// Formats a window-level numeric value to one decimal place.
    /// Formats a numeric window/level value for display with one decimal place.
    /// - Returns: `"N/A"` when `isValid` is false; otherwise a string representation of `value`
    ///   rounded to one digit after the decimal point (e.g., "12.3").
    private func formatWindowValue(_ value: Double, isValid: Bool) -> String {
        guard isValid else { return "N/A" }
        return String(format: "%.1f", value)
    }
}

// MARK: - Metadata Row Component

/// A single metadata row with label, value, and optional icon.
///
/// Displays a metadata field as a horizontal row with left-aligned label, optional
/// SF Symbols icon, and right-aligned value. The value displays as "N/A" if missing
/// or empty. Includes proper accessibility labels for VoiceOver support.
///
/// ## Usage
///
/// ```swift
/// MetadataRow(
///     label: "Patient Name",
///     value: "John Doe",
///     icon: "person.fill"
/// )
/// ```
@available(iOS 13.0, macOS 12.0, *)
private struct MetadataRow: View {
    /// The field label displayed on the left
    let label: String

    /// The field value displayed on the right (optional)
    let value: String?

    /// Optional SF Symbols icon name displayed before the label
    let icon: String?

    /// Creates a metadata row.
    ///
    /// - Parameters:
    ///   - label: The field label (e.g., "Patient Name")
    ///   - value: The field value (displays "N/A" if nil or empty)
    ///   - icon: Optional SF Symbols icon name
    init(label: String, value: String?, icon: String? = nil) {
        self.label = label
        self.value = value
        self.icon = icon
    }

    var body: some View {
        HStack {
            if let icon = icon {
                Image(systemName: icon)
                    .foregroundColor(.secondary)
                    .font(.body)
                    .frame(width: 24)
                    .accessibilityHidden(true)
            }

            Text(label)
                .foregroundColor(.primary)

            Spacer()

            Text(displayValue)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.trailing)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(displayValue)")
    }

    /// The display value, returning "N/A" for missing or empty values
    private var displayValue: String {
        if let value = value, !value.isEmpty {
            return value
        }
        return "N/A"
    }
}

// MARK: - Helper Extensions

@available(iOS 13.0, macOS 12.0, *)
private extension View {
    /// Applies inline navigation bar title display mode on iOS only.
    ///
    /// Convenience modifier that applies `.navigationBarTitleDisplayMode(.inline)` on iOS
    /// and does nothing on other platforms where this modifier is unavailable. Used in
    /// Applies an inline navigation bar title display mode on iOS; does nothing on other platforms.
    /// Applies an inline navigation bar title display mode on iOS; on other platforms the view is unchanged.
    /// - Returns: The view modified to use an inline navigation bar title display mode on iOS, or the original view on other platforms.
    @ViewBuilder
    func inlineNavigationBarTitle() -> some View {
        #if os(iOS)
        if #available(iOS 14.0, *) {
            self.navigationBarTitleDisplayMode(.inline)
        } else {
            self
        }
        #else
        self
        #endif
    }
}

// MARK: - SwiftUI Previews

#if DEBUG
@available(iOS 13.0, macOS 12.0, *)
struct MetadataView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            // List style with CT sample
            NavigationView {
                MetadataView(decoder: createCTDecoder(), style: .list)
                    .navigationTitle("CT Scan Metadata")
                    .inlineNavigationBarTitle()
            }
            .previewDisplayName("List Style - CT")

            // Form style with MRI sample
            NavigationView {
                MetadataView(decoder: createMRIDecoder(), style: .form)
                    .navigationTitle("MRI Metadata")
                    .inlineNavigationBarTitle()
            }
            .previewDisplayName("Form Style - MRI")

            // X-Ray in dark mode
            NavigationView {
                MetadataView(decoder: createXRayDecoder())
                    .navigationTitle("X-Ray Metadata")
                    .inlineNavigationBarTitle()
            }
            .preferredColorScheme(.dark)
            .previewDisplayName("Dark Mode - X-Ray")

            // Ultrasound in light mode
            NavigationView {
                MetadataView(decoder: createUltrasoundDecoder())
                    .navigationTitle("Ultrasound Metadata")
                    .inlineNavigationBarTitle()
            }
            .preferredColorScheme(.light)
            .previewDisplayName("Light Mode - Ultrasound")

            // Minimal metadata (missing fields)
            NavigationView {
                MetadataView(decoder: createMinimalDecoder())
                    .navigationTitle("DICOM Metadata")
                    .inlineNavigationBarTitle()
            }
            .previewDisplayName("Minimal Data")
        }
    }

    /// Creates a CT scan decoder with comprehensive metadata for preview.
    ///
    /// - Returns: A mock decoder with CT chest scan metadata including patient info,
    ///            study details, and technical imaging parameters.
    private static func createCTDecoder() -> MockDicomDecoderForPreviews {
        return MockDicomDecoderForPreviews(
            width: 512,
            height: 512,
            bitDepth: 16,
            samplesPerPixel: 1,
            windowCenter: -600.0,
            windowWidth: 1500.0,
            pixelWidth: 0.7,
            pixelHeight: 0.7,
            pixelDepth: 5.0,
            metadata: [
                "00100010": "Smith^John",           // Patient Name
                "00100020": "CT123456",             // Patient ID
                "00100040": "M",                    // Patient Sex
                "00101010": "055Y",                 // Patient Age
                "00081030": "CT Chest",             // Study Description
                "00080020": "20240215",             // Study Date
                "00080030": "143025",               // Study Time
                "00200010": "STU20240215143025",    // Study ID
                "00080060": "CT",                   // Modality
                "00080080": "General Hospital",     // Institution Name
                "0008103E": "Lung Window",          // Series Description
                "00200011": "1",                    // Series Number
                "00200013": "42",                   // Instance Number
                "00201209": "125",                  // Number of Series Related Instances
                "00180050": "5.0",                  // Slice Thickness
                "00280100": "16",                   // Bits Allocated
                "00280004": "MONOCHROME2"           // Photometric Interpretation
            ]
        )
    }

    /// Creates an MRI decoder with brain scan metadata for preview.
    ///
    /// - Returns: A mock decoder with MRI brain scan metadata including T1-weighted
    ///            sequence information and patient demographics.
    private static func createMRIDecoder() -> MockDicomDecoderForPreviews {
        return MockDicomDecoderForPreviews(
            width: 256,
            height: 256,
            bitDepth: 16,
            samplesPerPixel: 1,
            windowCenter: 600.0,
            windowWidth: 1200.0,
            pixelWidth: 0.9,
            pixelHeight: 0.9,
            pixelDepth: 3.0,
            metadata: [
                "00100010": "Doe^Jane",             // Patient Name
                "00100020": "MR789012",             // Patient ID
                "00100040": "F",                    // Patient Sex
                "00101010": "032Y",                 // Patient Age
                "00081030": "MRI Brain",            // Study Description
                "00080020": "20240214",             // Study Date
                "00080030": "091530",               // Study Time
                "00200010": "STU20240214091530",    // Study ID
                "00080060": "MR",                   // Modality
                "00080080": "University Medical",   // Institution Name
                "0008103E": "T1 Weighted",          // Series Description
                "00200011": "2",                    // Series Number
                "00200013": "18",                   // Instance Number
                "00201209": "80",                   // Number of Series Related Instances
                "00180050": "3.0",                  // Slice Thickness
                "00280100": "16",                   // Bits Allocated
                "00280004": "MONOCHROME2"           // Photometric Interpretation
            ]
        )
    }

    /// Creates an X-ray decoder with chest radiograph metadata for preview.
    ///
    /// - Returns: A mock decoder with chest X-ray metadata in PA view configuration.
    private static func createXRayDecoder() -> MockDicomDecoderForPreviews {
        return MockDicomDecoderForPreviews(
            width: 1024,
            height: 1024,
            bitDepth: 16,
            samplesPerPixel: 1,
            windowCenter: 2000.0,
            windowWidth: 4000.0,
            pixelWidth: 0.2,
            pixelHeight: 0.2,
            pixelDepth: 1.0,
            metadata: [
                "00100010": "Johnson^Robert",       // Patient Name
                "00100020": "XR345678",             // Patient ID
                "00100040": "M",                    // Patient Sex
                "00101010": "047Y",                 // Patient Age
                "00081030": "Chest X-Ray",          // Study Description
                "00080020": "20240216",             // Study Date
                "00080030": "161045",               // Study Time
                "00200010": "STU20240216161045",    // Study ID
                "00080060": "CR",                   // Modality (Computed Radiography)
                "00080080": "City Imaging Center",  // Institution Name
                "0008103E": "PA View",              // Series Description
                "00200011": "1",                    // Series Number
                "00200013": "1",                    // Instance Number
                "00201209": "1",                    // Number of Series Related Instances
                "00180050": "1.0",                  // Slice Thickness
                "00280100": "16",                   // Bits Allocated
                "00280004": "MONOCHROME2"           // Photometric Interpretation
            ]
        )
    }

    /// Creates an ultrasound decoder with abdominal scan metadata for preview.
    ///
    /// - Returns: A mock decoder with ultrasound metadata showing 8-bit image configuration.
    private static func createUltrasoundDecoder() -> MockDicomDecoderForPreviews {
        return MockDicomDecoderForPreviews(
            width: 640,
            height: 480,
            bitDepth: 8,
            samplesPerPixel: 1,
            windowCenter: 128.0,
            windowWidth: 256.0,
            pixelWidth: 0.1,
            pixelHeight: 0.1,
            pixelDepth: 1.0,
            metadata: [
                "00100010": "Williams^Mary",        // Patient Name
                "00100020": "US901234",             // Patient ID
                "00100040": "F",                    // Patient Sex
                "00101010": "028Y",                 // Patient Age
                "00081030": "Ultrasound Exam",      // Study Description
                "00080020": "20240217",             // Study Date
                "00080030": "104515",               // Study Time
                "00200010": "STU20240217104515",    // Study ID
                "00080060": "US",                   // Modality
                "00080080": "Downtown Clinic",      // Institution Name
                "0008103E": "Abdomen",              // Series Description
                "00200011": "1",                    // Series Number
                "00200013": "25",                   // Instance Number
                "00201209": "50",                   // Number of Series Related Instances
                "00180050": "1.0",                  // Slice Thickness
                "00280100": "8",                    // Bits Allocated
                "00280004": "MONOCHROME2"           // Photometric Interpretation
            ]
        )
    }

    /// Creates a minimal decoder with empty metadata for testing "N/A" display.
    ///
    /// - Returns: A mock decoder with minimal configuration to verify graceful
    ///            handling of missing metadata fields.
    private static func createMinimalDecoder() -> MockDicomDecoderForPreviews {
        return MockDicomDecoderForPreviews(
            width: 512,
            height: 512,
            metadata: [:]
        )
    }
}
#endif
