//
//  PaletteTagHandler.swift
//
//  Handler for DICOM palette color lookup table tags: Red Palette
//  (0028,1201), Green Palette (0028,1202), and Blue Palette
//  (0028,1203).  These tags define color lookup tables (LUTs) for
//  converting grayscale pixel values to RGB color values in
//  PALETTE COLOR images.
//
//  Supported Tags:
//
//  - Red Palette Color Lookup Table Data (0028,1201)
//  - Green Palette Color Lookup Table Data (0028,1202)
//  - Blue Palette Color Lookup Table Data (0028,1203)
//
//  PALETTE COLOR Images:
//
//  Some DICOM images (particularly ultrasound and nuclear medicine)
//  use palette color mode where pixel values are indices into color
//  lookup tables rather than direct RGB values.  The palette tags
//  store the red, green, and blue intensity mappings.
//
//  Each LUT is stored as a sequence of 16-bit values, but only the
//  high 8 bits are used for display (low 8 bits are discarded).
//  The `readLUT()` method automatically performs this conversion.
//
//  Color Mapping:
//
//  For a pixel with grayscale value `i`:
//    red[i]   = reds[i]    // Red intensity (0-255)
//    green[i] = greens[i]  // Green intensity (0-255)
//    blue[i]  = blues[i]   // Blue intensity (0-255)
//
//  Typical LUT sizes are 256 entries (8-bit indices) or 4096 entries
//  (12-bit indices).
//
//  Thread Safety:
//
//  This handler is thread-safe when used as intended: each DCMDecoder
//  instance processes one file on a single thread.  No internal state
//  is maintained between handle() calls.
//
//  Usage:
//
//  The handler is invoked automatically by TagHandlerRegistry when
//  any of the palette tags are encountered during file parsing.
//  Client code does not interact with this class directly.
//

import Foundation

/// Backward compatibility alias to centralized DICOM tag constants.
private typealias Tag = DicomTag

/// Handler for DICOM palette color lookup table tags (Red, Green, Blue Palette).
/// Extracts color lookup tables from the DICOM stream and updates the decoder
/// context for PALETTE COLOR image rendering.
///
/// **Processing Steps:**
///
/// 1. Determines which palette tag is being processed
/// 2. Gets the element length from the tag parser
/// 3. Calls `reader.readLUT()` to read and convert the 16-bit LUT to 8-bit
/// 4. If successful, updates the corresponding context property:
///    - Red Palette → `context.reds`
///    - Green Palette → `context.greens`
///    - Blue Palette → `context.blues`
/// 5. Adds the LUT size (entry count) to the metadata dictionary
///
/// **Example DICOM Data:**
///
///     (0028,1201) OW [16-bit red values]     # Red Palette
///     (0028,1202) OW [16-bit green values]   # Green Palette
///     (0028,1203) OW [16-bit blue values]    # Blue Palette
///
/// After processing, `context.reds`, `context.greens`, and `context.blues`
/// will each contain 256 or 4096 UInt8 values representing color intensities.
///
/// **Error Handling:**
///
/// If `readLUT()` returns nil (malformed data or odd length), the handler
/// silently skips that palette.  The image can still be displayed as
/// grayscale if all three palettes fail to load.
internal final class PaletteTagHandler: TagHandler {

    // MARK: - TagHandler Protocol

    /// Processes a palette color lookup table tag and updates decoder context.
    ///
    /// - Parameters:
    ///   - tag: The DICOM tag ID (Red, Green, or Blue Palette)
    ///   - reader: Binary reader for extracting the LUT data
    ///   - location: Current read position (advanced by read operations)
    ///   - parser: Tag parser providing element length information
    ///   - context: Decoder context to update with palette data
    ///   - addInfo: Unused by this handler (uses addInfoInt instead)
    ///   - addInfoInt: Callback to add LUT size to the metadata dictionary
    ///
    /// - Returns: Always returns `true` to continue processing subsequent tags.
    func handle(
        tag: Int,
        reader: DCMBinaryReader,
        location: inout Int,
        parser: DCMTagParser,
        context: DecoderContext,
        addInfo: (Int, String?) -> Void,
        addInfoInt: (Int, Int) -> Void
    ) -> Bool {
        // Get element length from parser
        let elementLength = parser.currentElementLength

        // Read lookup table from DICOM stream (converts 16-bit to 8-bit)
        if let table = reader.readLUT(length: elementLength, location: &location) {
            // Update the appropriate context property based on tag type
            switch tag {
            case Tag.redPalette.rawValue:
                context.reds = table
                addInfoInt(tag, table.count)

            case Tag.greenPalette.rawValue:
                context.greens = table
                addInfoInt(tag, table.count)

            case Tag.bluePalette.rawValue:
                context.blues = table
                addInfoInt(tag, table.count)

            default:
                // Should not reach here if registry is configured correctly
                break
            }
        }
        // If readLUT returns nil, the location is already advanced
        // and we silently skip this palette (graceful degradation)

        // Continue processing subsequent tags
        return true
    }
}
