import Foundation
import simd

public struct DicomJP3DVolumeGeometry: Sendable {
    public let dimensions: DicomSeriesDimensions
    public let spacing: SIMD3<Double>
    public let orientation: simd_double3x3
    public let origin: SIMD3<Double>
    public let rescaleSlope: Double
    public let rescaleIntercept: Double
    public let bitsAllocated: Int
    public let isSignedPixel: Bool
    public let patientName: String
    public let seriesDescription: String
    public let modality: String
    public let windowCenter: Double?
    public let windowWidth: Double?
    public let studyInstanceUID: String?
    public let seriesInstanceUID: String?
    public let frameOfReferenceUID: String?

    public init(dimensions: DicomSeriesDimensions,
                spacing: SIMD3<Double>,
                orientation: simd_double3x3 = matrix_identity_double3x3,
                origin: SIMD3<Double> = SIMD3<Double>(0, 0, 0),
                rescaleSlope: Double = 1,
                rescaleIntercept: Double = 0,
                bitsAllocated: Int = 16,
                isSignedPixel: Bool = false,
                patientName: String = "",
                seriesDescription: String = "",
                modality: String = "",
                windowCenter: Double? = nil,
                windowWidth: Double? = nil,
                studyInstanceUID: String? = nil,
                seriesInstanceUID: String? = nil,
                frameOfReferenceUID: String? = nil) {
        self.dimensions = dimensions
        self.spacing = spacing
        self.orientation = orientation
        self.origin = origin
        self.rescaleSlope = rescaleSlope
        self.rescaleIntercept = rescaleIntercept
        self.bitsAllocated = bitsAllocated
        self.isSignedPixel = isSignedPixel
        self.patientName = patientName
        self.seriesDescription = seriesDescription
        self.modality = modality
        self.windowCenter = windowCenter
        self.windowWidth = windowWidth
        self.studyInstanceUID = studyInstanceUID
        self.seriesInstanceUID = seriesInstanceUID
        self.frameOfReferenceUID = frameOfReferenceUID
    }
}

public struct DicomJP3DVolumeDocument: Sendable {
    public static var isCodecAvailable: Bool {
        DicomJPEG2000Codec.isAvailable
    }

    public let compressedData: Data
    public let transferSyntax: DicomTransferSyntax
    public let geometry: DicomJP3DVolumeGeometry
    public let sourceURL: URL?

    public init(compressedData: Data,
                transferSyntax: DicomTransferSyntax,
                geometry: DicomJP3DVolumeGeometry,
                sourceURL: URL? = nil) throws {
        guard transferSyntax.isJPEG2000Part2Multicomponent else {
            throw DICOMError.unsupportedTransferSyntax(syntax: transferSyntax.rawValue)
        }
        guard !compressedData.isEmpty else {
            throw DICOMError.invalidPixelData(reason: "JP3D volume payload is empty")
        }
        guard geometry.dimensions.width > 0,
              geometry.dimensions.height > 0,
              geometry.dimensions.depth > 0 else {
            throw DICOMError.invalidPixelData(reason: "JP3D volume dimensions are invalid")
        }
        guard geometry.bitsAllocated > 0, geometry.bitsAllocated <= 16 else {
            throw DICOMError.invalidPixelData(reason: "JP3D volume bit allocation \(geometry.bitsAllocated) is unsupported")
        }

        self.compressedData = compressedData
        self.transferSyntax = transferSyntax
        self.geometry = geometry
        self.sourceURL = sourceURL
    }

    public init(contentsOf url: URL) throws {
        let decoder = try DCMDecoder(contentsOf: url)
        try self.init(decoder: decoder, sourceURL: url)
    }

    public init(decoder: DCMDecoder, sourceURL: URL? = nil) throws {
        let snapshot = try decoder.synchronized {
            try Self.makeDocumentSnapshot(from: decoder)
        }
        try self.init(
            compressedData: snapshot.compressedData,
            transferSyntax: snapshot.transferSyntax,
            geometry: snapshot.geometry,
            sourceURL: sourceURL
        )
    }

    public func decodedVolume() throws -> DicomSeriesVolume {
        let decoded = try DicomJPEG2000Codec.decodeVolume(compressedData)
        guard decoded.width == geometry.dimensions.width,
              decoded.height == geometry.dimensions.height,
              decoded.depth == geometry.dimensions.depth else {
            throw DICOMError.invalidPixelData(
                reason: "JP3D decoded dimensions \(decoded.width)x\(decoded.height)x\(decoded.depth) do not match DICOM geometry \(geometry.dimensions.width)x\(geometry.dimensions.height)x\(geometry.dimensions.depth)"
            )
        }
        guard decoded.isSigned == geometry.isSignedPixel else {
            throw DICOMError.invalidPixelData(reason: "JP3D codestream signedness does not match DICOM Pixel Representation")
        }
        guard decoded.bitsPerSample <= geometry.bitsAllocated else {
            throw DICOMError.invalidPixelData(reason: "JP3D codestream precision exceeds DICOM Bits Allocated")
        }

        return DicomSeriesVolume(
            voxels: decoded.voxels,
            width: decoded.width,
            height: decoded.height,
            depth: decoded.depth,
            spacing: geometry.spacing,
            orientation: geometry.orientation,
            origin: geometry.origin,
            rescaleSlope: geometry.rescaleSlope,
            rescaleIntercept: geometry.rescaleIntercept,
            bitsAllocated: 16,
            isSignedPixel: geometry.isSignedPixel,
            patientName: geometry.patientName,
            seriesDescription: geometry.seriesDescription,
            modality: geometry.modality,
            windowCenter: geometry.windowCenter,
            windowWidth: geometry.windowWidth,
            studyInstanceUID: geometry.studyInstanceUID,
            seriesInstanceUID: geometry.seriesInstanceUID,
            frameOfReferenceUID: geometry.frameOfReferenceUID
        )
    }

    public func decodedSeries() throws -> DicomDecodedSeries {
        let resolvedSourceURL = sourceURL ?? FileManager.default.temporaryDirectory
            .appendingPathComponent("DicomJP3DVolumeDocument")
        return try DicomDecodedSeries(volume: decodedVolume(), sourceURL: resolvedSourceURL)
    }
}

private struct DicomJP3DDocumentSnapshot {
    let compressedData: Data
    let transferSyntax: DicomTransferSyntax
    let geometry: DicomJP3DVolumeGeometry
}

private extension DicomJP3DVolumeDocument {
    static func makeDocumentSnapshot(from decoder: DCMDecoder) throws -> DicomJP3DDocumentSnapshot {
        guard let transferSyntax = DicomTransferSyntax(uid: decoder.transferSyntaxUID),
              transferSyntax.isJPEG2000Part2Multicomponent else {
            let uid = decoder.transferSyntaxUID.isEmpty ? "<unknown>" : decoder.transferSyntaxUID
            throw DICOMError.unsupportedTransferSyntax(syntax: uid)
        }
        guard let descriptor = decoder.makeEncapsulatedPixelDataDescriptorUnsafe(),
              !descriptor.fragments.isEmpty else {
            throw DICOMError.invalidPixelData(reason: "JP3D DICOM object has no encapsulated component collection")
        }

        var compressedData = Data()
        for fragment in descriptor.fragments {
            guard fragment.valueRange.lowerBound >= 0,
                  fragment.valueRange.upperBound <= decoder.dicomData.count else {
                throw DICOMError.invalidPixelData(reason: "JP3D fragment range is outside Pixel Data")
            }
            compressedData.append(Data(decoder.dicomData[fragment.valueRange]))
        }

        return DicomJP3DDocumentSnapshot(
            compressedData: compressedData,
            transferSyntax: transferSyntax,
            geometry: makeGeometry(from: decoder)
        )
    }

    static func makeGeometry(from decoder: DCMDecoder) -> DicomJP3DVolumeGeometry {
        let orientation: simd_double3x3
        if let imageOrientation = decoder.imageOrientation {
            orientation = orientationMatrix(row: imageOrientation.row, column: imageOrientation.column)
        } else {
            orientation = matrix_identity_double3x3
        }

        return DicomJP3DVolumeGeometry(
            dimensions: DicomSeriesDimensions(
                width: decoder.width,
                height: decoder.height,
                depth: max(1, decoder.nImages)
            ),
            spacing: SIMD3<Double>(
                validSpacing(decoder.pixelWidth),
                validSpacing(decoder.pixelHeight),
                validSpacing(decoder.pixelDepth)
            ),
            orientation: orientation,
            origin: decoder.imagePosition ?? SIMD3<Double>(0, 0, 0),
            rescaleSlope: decoder.rescaleParametersV2.slope,
            rescaleIntercept: decoder.rescaleParametersV2.intercept,
            bitsAllocated: decoder.bitDepth,
            isSignedPixel: decoder.pixelRepresentationTagValue == 1,
            patientName: decoder.info(for: .patientName),
            seriesDescription: decoder.info(for: .seriesDescription),
            modality: decoder.info(for: .modality),
            windowCenter: decoder.doubleValue(for: .windowCenter),
            windowWidth: decoder.doubleValue(for: .windowWidth),
            studyInstanceUID: nonEmpty(decoder.info(for: .studyInstanceUID)),
            seriesInstanceUID: nonEmpty(decoder.info(for: .seriesInstanceUID)),
            frameOfReferenceUID: nonEmpty(decoder.info(for: 0x0020_0052))
        )
    }

    static func orientationMatrix(row: SIMD3<Double>, column: SIMD3<Double>) -> simd_double3x3 {
        let normal = simd_cross(row, column)
        let normalLength = simd_length(normal)
        let slice = normalLength > Double.ulpOfOne ? normal / normalLength : SIMD3<Double>(0, 0, 1)
        return simd_double3x3(columns: (row, column, slice))
    }

    static func validSpacing(_ value: Double) -> Double {
        value > 0 ? value : 1
    }

    static func nonEmpty(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

private extension DicomTransferSyntax {
    var isJPEG2000Part2Multicomponent: Bool {
        switch self {
        case .jpeg2000Part2MulticomponentLossless,
             .jpeg2000Part2Multicomponent:
            return true
        default:
            return false
        }
    }
}
