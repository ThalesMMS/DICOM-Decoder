//
//  DicomConstants.swift
//
//  Centralized DICOM constants including tag definitions, Value
//  Representations, and transfer syntax UIDs. This module provides
//  type-safe enums to replace scattered magic numbers across the
//  codebase and improve maintainability.
//
//  Usage:
//
//    let decoder = DCMDecoder()
//    let patientName = decoder.info(for: DicomTag.patientName.rawValue)
//

import Foundation

// MARK: - DICOM Tag Constants

/// DICOM tag identifiers following the DICOM standard format.
/// Each tag is a 32-bit value combining group and element numbers
/// (0xGGGGEEEE). Tags are organized by category for clarity.
public enum DicomTag: Int {

    // MARK: - Image Pixel Description

    /// (0028,0002) - Samples per Pixel
    case samplesPerPixel = 0x00280002

    /// (0028,0004) - Photometric Interpretation (e.g., MONOCHROME1, RGB)
    case photometricInterpretation = 0x00280004

    /// (0028,0006) - Planar Configuration
    case planarConfiguration = 0x00280006

    /// (0028,0008) - Number of Frames
    case numberOfFrames = 0x00280008

    /// (0028,0010) - Rows (image height)
    case rows = 0x00280010

    /// (0028,0011) - Columns (image width)
    case columns = 0x00280011

    /// (0028,0030) - Pixel Spacing
    case pixelSpacing = 0x00280030

    /// (0028,0100) - Bits Allocated
    case bitsAllocated = 0x00280100

    /// (0028,0101) - Bits Stored
    case bitsStored = 0x00280101

    /// (0028,0102) - High Bit
    case highBit = 0x00280102

    /// (0028,0103) - Pixel Representation (0=unsigned, 1=signed)
    case pixelRepresentation = 0x00280103

    // MARK: - Image Display Parameters

    /// (0028,1050) - Window Center
    case windowCenter = 0x00281050

    /// (0028,1051) - Window Width
    case windowWidth = 0x00281051

    /// (0028,1052) - Rescale Intercept
    case rescaleIntercept = 0x00281052

    /// (0028,1053) - Rescale Slope
    case rescaleSlope = 0x00281053

    // MARK: - Color Palettes

    /// (0028,1201) - Red Palette Color Lookup Table
    case redPalette = 0x00281201

    /// (0028,1202) - Green Palette Color Lookup Table
    case greenPalette = 0x00281202

    /// (0028,1203) - Blue Palette Color Lookup Table
    case bluePalette = 0x00281203

    // MARK: - Pixel Data

    /// (7FE0,0010) - Pixel Data
    case pixelData = 0x7FE00010

    /// (0088,0200) - Icon Image Sequence
    case iconImageSequence = 0x00880200

    // MARK: - Patient Information

    /// (0010,0010) - Patient's Name
    case patientName = 0x00100010

    /// (0010,0020) - Patient ID
    case patientID = 0x00100020

    /// (0010,0040) - Patient's Sex
    case patientSex = 0x00100040

    /// (0010,1010) - Patient's Age
    case patientAge = 0x00101010

    // MARK: - Study Information

    /// (0020,000D) - Study Instance UID
    case studyInstanceUID = 0x0020000d

    /// (0020,0010) - Study ID
    case studyID = 0x00200010

    /// (0008,0020) - Study Date
    case studyDate = 0x00080020

    /// (0008,0030) - Study Time
    case studyTime = 0x00080030

    /// (0008,1030) - Study Description
    case studyDescription = 0x00081030

    /// (0020,1206) - Number of Study Related Series
    case numberOfStudyRelatedSeries = 0x00201206

    /// (0008,0061) - Modalities in Study
    case modalitiesInStudy = 0x00080061

    /// (0008,0090) - Referring Physician's Name
    case referringPhysicianName = 0x00080090

    // MARK: - Series Information

    /// (0020,000E) - Series Instance UID
    case seriesInstanceUID = 0x0020000e

    /// (0020,0011) - Series Number
    case seriesNumber = 0x00200011

    /// (0008,0021) - Series Date
    case seriesDate = 0x00080021

    /// (0008,0031) - Series Time
    case seriesTime = 0x00080031

    /// (0008,103E) - Series Description
    case seriesDescription = 0x0008103E

    /// (0020,1209) - Number of Series Related Instances
    case numberOfSeriesRelatedInstances = 0x00201209

    /// (0008,0060) - Modality
    case modality = 0x00080060

    // MARK: - Protocol Names

    /// (0028,1030) - Protocol Name (Image level)
    case protocolName = 0x00281030

    /// (0018,1030) - Protocol Name (Acquisition level)
    case acquisitionProtocolName = 0x00181030

    // MARK: - Image Position and Orientation

    /// (0020,0032) - Image Position (Patient)
    case imagePositionPatient = 0x00200032

    /// (0020,0037) - Image Orientation (Patient)
    case imageOrientationPatient = 0x00200037

    /// (0018,0050) - Slice Thickness
    case sliceThickness = 0x00180050

    /// (0018,0088) - Spacing Between Slices
    case sliceSpacing = 0x00180088

    // MARK: - Instance Information

    /// (0008,0018) - SOP Instance UID
    case sopInstanceUID = 0x00080018

    /// (0020,0013) - Instance Number
    case instanceNumber = 0x00200013

    /// (0008,0022) - Acquisition Date
    case acquisitionDate = 0x00080022

    /// (0008,0023) - Content Date
    case contentDate = 0x00080023

    /// (0008,0032) - Acquisition Time
    case acquisitionTime = 0x00080032

    /// (0008,0033) - Content Time
    case contentTime = 0x00080033

    // MARK: - Acquisition Parameters

    /// (0018,5100) - Patient Position
    case patientPosition = 0x00185100

    /// (0018,0015) - Body Part Examined
    case bodyPartExamined = 0x00180015

    // MARK: - Institutional Information

    /// (0008,0080) - Institution Name
    case institutionName = 0x00080080

    // MARK: - Transfer Syntax

    /// (0002,0010) - Transfer Syntax UID
    case transferSyntaxUID = 0x00020010
}

// MARK: - DICOM Value Representation (VR)

/// Value Representation codes expressed as their 16-bit ASCII
/// representation. These values correspond to the two-character
/// VR codes defined in the DICOM standard (e.g., AE, AS, AT).
/// Implicit VR is represented by `implicitRaw` which is the
/// value of two hyphens (0x2D2D). Unknown VR is represented
/// by `unknown`.
public enum DicomVR: Int {

    // MARK: - String Types

    /// Application Entity (max 16 chars)
    case AE = 0x4145

    /// Age String (4 chars fixed)
    case AS = 0x4153

    /// Attribute Tag (4 bytes)
    case AT = 0x4154

    /// Code String (max 16 chars)
    case CS = 0x4353

    /// Date (8 bytes fixed, YYYYMMDD)
    case DA = 0x4441

    /// Decimal String (max 16 chars)
    case DS = 0x4453

    /// Date Time (max 26 chars)
    case DT = 0x4454

    /// Long String (max 64 chars)
    case LO = 0x4C4F

    /// Long Text (max 10240 chars)
    case LT = 0x4C54

    /// Person Name (max 64 chars per component)
    case PN = 0x504E

    /// Short String (max 16 chars)
    case SH = 0x5348

    /// Short Text (max 1024 chars)
    case ST = 0x5354

    /// Time (max 16 chars)
    case TM = 0x544D

    /// Unique Identifier (max 64 chars)
    case UI = 0x5549

    /// Unlimited Text (max 2^32-2 chars)
    case UT = 0x5554

    // MARK: - Numeric Types

    /// Floating Point Double (8 bytes)
    case FD = 0x4644

    /// Floating Point Single (4 bytes)
    case FL = 0x464C

    /// Integer String (max 12 chars)
    case IS = 0x4953

    /// Signed Long (4 bytes)
    case SL = 0x534C

    /// Signed Short (2 bytes)
    case SS = 0x5353

    /// Unsigned Long (4 bytes)
    case UL = 0x554C

    /// Unsigned Short (2 bytes)
    case US = 0x5553

    // MARK: - Binary Types

    /// Other Byte (variable length)
    case OB = 0x4F42

    /// Other Word (variable length)
    case OW = 0x4F57

    /// Sequence of Items
    case SQ = 0x5351

    /// Unknown (variable length)
    case UN = 0x554E

    // MARK: - Special Cases

    /// Query/Retrieve Level (retired)
    case QQ = 0x3F3F

    /// Retired (variable length)
    case RT = 0x5254

    /// Implicit VR (represented as "--")
    case implicitRaw = 0x2D2D

    /// Unknown or unrecognized VR
    case unknown = 0

    // MARK: - Helper Methods

    /// Returns true if this VR expects a 32-bit length field when
    /// using explicit VR encoding. Most VRs use 16-bit length
    /// fields, but OB, OW, SQ, UN, and UT require 32-bit lengths
    /// to accommodate larger data elements.
    public var uses32BitLength: Bool {
        switch self {
        case .OB, .OW, .SQ, .UN, .UT:
            return true
        default:
            return false
        }
    }
}

// MARK: - DICOM Transfer Syntax UIDs

/// DICOM transfer syntax unique identifiers (UIDs) as defined in
/// the DICOM standard Part 5. Transfer syntaxes specify the encoding
/// rules used for the DICOM file, including byte ordering (endianness),
/// VR encoding (explicit vs implicit), and pixel data compression.
public enum DicomTransferSyntax: String {

    // MARK: - Uncompressed Transfer Syntaxes

    /// Implicit VR Little Endian (Default Transfer Syntax for DICOM)
    /// UID: 1.2.840.10008.1.2
    case implicitVRLittleEndian = "1.2.840.10008.1.2"

    /// Explicit VR Little Endian
    /// UID: 1.2.840.10008.1.2.1
    case explicitVRLittleEndian = "1.2.840.10008.1.2.1"

    /// Explicit VR Big Endian (Retired)
    /// UID: 1.2.840.10008.1.2.2
    case explicitVRBigEndian = "1.2.840.10008.1.2.2"

    // MARK: - JPEG Compressed Transfer Syntaxes

    /// JPEG Baseline (Process 1): Default Transfer Syntax for Lossy
    /// JPEG 8 Bit Image Compression
    /// UID: 1.2.840.10008.1.2.4.50
    case jpegBaseline = "1.2.840.10008.1.2.4.50"

    /// JPEG Extended (Process 2 & 4): Default Transfer Syntax for
    /// Lossy JPEG 12 Bit Image Compression
    /// UID: 1.2.840.10008.1.2.4.51
    case jpegExtended = "1.2.840.10008.1.2.4.51"

    /// JPEG Lossless, Non-Hierarchical (Process 14)
    /// UID: 1.2.840.10008.1.2.4.57
    case jpegLossless = "1.2.840.10008.1.2.4.57"

    /// JPEG Lossless, Non-Hierarchical, First-Order Prediction
    /// (Process 14 [Selection Value 1])
    /// UID: 1.2.840.10008.1.2.4.70
    case jpegLosslessFirstOrder = "1.2.840.10008.1.2.4.70"

    // MARK: - JPEG-LS Compressed Transfer Syntaxes

    /// JPEG-LS Lossless Image Compression
    /// UID: 1.2.840.10008.1.2.4.80
    case jpegLSLossless = "1.2.840.10008.1.2.4.80"

    /// JPEG-LS Lossy (Near-Lossless) Image Compression
    /// UID: 1.2.840.10008.1.2.4.81
    case jpegLSNearLossless = "1.2.840.10008.1.2.4.81"

    // MARK: - JPEG 2000 Compressed Transfer Syntaxes

    /// JPEG 2000 Image Compression (Lossless Only)
    /// UID: 1.2.840.10008.1.2.4.90
    case jpeg2000Lossless = "1.2.840.10008.1.2.4.90"

    /// JPEG 2000 Image Compression
    /// UID: 1.2.840.10008.1.2.4.91
    case jpeg2000 = "1.2.840.10008.1.2.4.91"

    // MARK: - RLE Compressed Transfer Syntax

    /// RLE Lossless
    /// UID: 1.2.840.10008.1.2.5
    case rleLossless = "1.2.840.10008.1.2.5"

    // MARK: - Helper Methods

    /// Returns true if this transfer syntax requires decompression
    /// before pixel data can be accessed. The decoder currently
    /// supports limited decompression via ImageIO for single-frame
    /// JPEG and JPEG 2000 images.
    public var isCompressed: Bool {
        switch self {
        case .implicitVRLittleEndian,
             .explicitVRLittleEndian,
             .explicitVRBigEndian:
            return false
        case .jpegBaseline,
             .jpegExtended,
             .jpegLossless,
             .jpegLosslessFirstOrder,
             .jpegLSLossless,
             .jpegLSNearLossless,
             .jpeg2000Lossless,
             .jpeg2000,
             .rleLossless:
            return true
        }
    }

    /// Returns true if this transfer syntax uses big-endian byte
    /// ordering. Most DICOM files use little-endian encoding; big
    /// endian is rare and has been retired from the standard.
    public var isBigEndian: Bool {
        switch self {
        case .explicitVRBigEndian:
            return true
        default:
            return false
        }
    }

    /// Returns true if this transfer syntax uses explicit VR encoding.
    /// Explicit VR includes the two-character VR code in each data
    /// element, while implicit VR requires a data dictionary lookup.
    public var isExplicitVR: Bool {
        switch self {
        case .implicitVRLittleEndian:
            return false
        default:
            // All other transfer syntaxes use explicit VR
            return true
        }
    }

    /// Initializes a transfer syntax from a UID string. Returns nil
    /// if the UID is not recognized. The UID string may contain
    /// trailing whitespace or null characters, which are automatically
    /// trimmed.
    ///
    /// - Parameter uid: The transfer syntax UID string
    public init?(uid: String) {
        let trimmed = uid.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\0"))
        self.init(rawValue: trimmed)
    }

    /// Returns true if the UID string matches this transfer syntax,
    /// accounting for potential trailing whitespace or null padding.
    ///
    /// - Parameter uid: The UID string to check
    /// - Returns: True if the UID matches this transfer syntax
    public func matches(_ uid: String) -> Bool {
        let trimmed = uid.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\0"))
        return self.rawValue == trimmed
    }
}
