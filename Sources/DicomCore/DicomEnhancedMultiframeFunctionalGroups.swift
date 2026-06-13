import Foundation
import simd

/// Parsed Enhanced Multi-frame functional groups with resolved per-frame metadata.
public struct DicomEnhancedMultiframeFunctionalGroups: Equatable, Sendable {
    public let shared: DicomFrameFunctionalGroups?
    public let perFrame: [DicomFrameFunctionalGroups]
    public let frames: [DicomEnhancedFrame]

    public init(
        shared: DicomFrameFunctionalGroups?,
        perFrame: [DicomFrameFunctionalGroups],
        declaredFrameCount: Int
    ) {
        let frameCount = max(declaredFrameCount, perFrame.count)
        self.shared = shared
        self.perFrame = perFrame
        self.frames = (0..<frameCount).map { index in
            let resolved = perFrame[safe: index]?.resolving(shared: shared) ?? DicomFrameFunctionalGroups().resolving(shared: shared)
            return DicomEnhancedFrame(index: index, functionalGroups: resolved)
        }
    }

    public var frameCount: Int {
        frames.count
    }

    /// Frames sorted for volume/MPR construction using patient-space position when available.
    public var framesInSpatialOrder: [DicomEnhancedFrame] {
        frames.sorted { lhs, rhs in
            if lhs.functionalGroups.frameContent?.stackID != rhs.functionalGroups.frameContent?.stackID {
                return (lhs.functionalGroups.frameContent?.stackID ?? "") < (rhs.functionalGroups.frameContent?.stackID ?? "")
            }
            if let left = lhs.geometry?.positionAlongNormal,
               let right = rhs.geometry?.positionAlongNormal,
               left != right {
                return left < right
            }
            if let left = lhs.functionalGroups.frameContent?.inStackPositionNumber,
               let right = rhs.functionalGroups.frameContent?.inStackPositionNumber,
               left != right {
                return left < right
            }
            return lhs.index < rhs.index
        }
    }

    /// Frames sorted for cine/playback using temporal frame content when available.
    public var framesInTemporalOrder: [DicomEnhancedFrame] {
        frames.sorted { lhs, rhs in
            if let left = lhs.functionalGroups.frameContent?.temporalPositionIndex,
               let right = rhs.functionalGroups.frameContent?.temporalPositionIndex,
               left != right {
                return left < right
            }
            if let left = lhs.functionalGroups.frameContent?.frameAcquisitionNumber,
               let right = rhs.functionalGroups.frameContent?.frameAcquisitionNumber,
               left != right {
                return left < right
            }
            return lhs.index < rhs.index
        }
    }

    public func geometry(forFrame index: Int) -> DicomFrameGeometry? {
        frames[safe: index]?.geometry
    }
}

/// Functional group macros resolved for one frame.
public struct DicomFrameFunctionalGroups: Equatable, Sendable {
    public let frameContent: DicomFrameContent?
    public let pixelMeasures: DicomPixelMeasures?
    public let planePosition: DicomPlanePosition?
    public let planeOrientation: DicomPlaneOrientation?
    public let derivationImage: DicomDerivationImage?
    public let pixelValueTransformation: DicomPixelValueTransformation?

    public init(
        frameContent: DicomFrameContent? = nil,
        pixelMeasures: DicomPixelMeasures? = nil,
        planePosition: DicomPlanePosition? = nil,
        planeOrientation: DicomPlaneOrientation? = nil,
        derivationImage: DicomDerivationImage? = nil,
        pixelValueTransformation: DicomPixelValueTransformation? = nil
    ) {
        self.frameContent = frameContent
        self.pixelMeasures = pixelMeasures
        self.planePosition = planePosition
        self.planeOrientation = planeOrientation
        self.derivationImage = derivationImage
        self.pixelValueTransformation = pixelValueTransformation
    }

    public func resolving(shared: DicomFrameFunctionalGroups?) -> DicomFrameFunctionalGroups {
        DicomFrameFunctionalGroups(
            frameContent: frameContent ?? shared?.frameContent,
            pixelMeasures: pixelMeasures ?? shared?.pixelMeasures,
            planePosition: planePosition ?? shared?.planePosition,
            planeOrientation: planeOrientation ?? shared?.planeOrientation,
            derivationImage: derivationImage ?? shared?.derivationImage,
            pixelValueTransformation: pixelValueTransformation ?? shared?.pixelValueTransformation
        )
    }
}

/// One zero-based Enhanced Multi-frame frame with resolved functional groups.
public struct DicomEnhancedFrame: Equatable, Sendable {
    public let index: Int
    public let functionalGroups: DicomFrameFunctionalGroups
    public let geometry: DicomFrameGeometry?

    public init(index: Int, functionalGroups: DicomFrameFunctionalGroups) {
        self.index = index
        self.functionalGroups = functionalGroups
        self.geometry = DicomFrameGeometry(frameIndex: index, functionalGroups: functionalGroups)
    }
}

/// Frame Content Functional Group values used for spatial and temporal ordering.
public struct DicomFrameContent: Equatable, Sendable {
    public let dimensionIndexValues: [Int]
    public let stackID: String?
    public let inStackPositionNumber: Int?
    public let temporalPositionIndex: Int?
    public let frameAcquisitionNumber: Int?

    public init(
        dimensionIndexValues: [Int],
        stackID: String?,
        inStackPositionNumber: Int?,
        temporalPositionIndex: Int?,
        frameAcquisitionNumber: Int?
    ) {
        self.dimensionIndexValues = dimensionIndexValues
        self.stackID = stackID
        self.inStackPositionNumber = inStackPositionNumber
        self.temporalPositionIndex = temporalPositionIndex
        self.frameAcquisitionNumber = frameAcquisitionNumber
    }
}

/// Pixel Measures Functional Group values for physical pixel geometry.
public struct DicomPixelMeasures: Equatable, Sendable {
    public let pixelSpacing: SIMD2<Double>?
    public let sliceThickness: Double?
    public let spacingBetweenSlices: Double?

    public init(
        pixelSpacing: SIMD2<Double>?,
        sliceThickness: Double?,
        spacingBetweenSlices: Double?
    ) {
        self.pixelSpacing = pixelSpacing
        self.sliceThickness = sliceThickness
        self.spacingBetweenSlices = spacingBetweenSlices
    }
}

/// Pixel Value Transformation Functional Group rescale values.
public struct DicomPixelValueTransformation: Equatable, Sendable {
    public let rescaleIntercept: Double
    public let rescaleSlope: Double

    public init(rescaleIntercept: Double, rescaleSlope: Double) {
        self.rescaleIntercept = rescaleIntercept
        self.rescaleSlope = rescaleSlope
    }
}

/// Plane Position Functional Group values in patient coordinates.
public struct DicomPlanePosition: Equatable, Sendable {
    public let imagePositionPatient: SIMD3<Double>

    public init(imagePositionPatient: SIMD3<Double>) {
        self.imagePositionPatient = imagePositionPatient
    }
}

/// Plane Orientation Functional Group direction cosines in patient coordinates.
public struct DicomPlaneOrientation: Equatable, Sendable {
    public let row: SIMD3<Double>
    public let column: SIMD3<Double>

    public init(row: SIMD3<Double>, column: SIMD3<Double>) {
        self.row = row
        self.column = column
    }

    public var normal: SIMD3<Double> {
        simd_cross(row, column)
    }
}

/// Derivation Image Functional Group source references.
public struct DicomDerivationImage: Equatable, Sendable {
    public let sourceImages: [DicomSourceImageReference]

    public init(sourceImages: [DicomSourceImageReference]) {
        self.sourceImages = sourceImages
    }
}

/// Source image reference for a derived Enhanced Multi-frame frame.
public struct DicomSourceImageReference: Equatable, Sendable {
    public let referencedSOPClassUID: String?
    public let referencedSOPInstanceUID: String?
    public let referencedFrameNumbers: [Int]

    public init(
        referencedSOPClassUID: String?,
        referencedSOPInstanceUID: String?,
        referencedFrameNumbers: [Int]
    ) {
        self.referencedSOPClassUID = referencedSOPClassUID
        self.referencedSOPInstanceUID = referencedSOPInstanceUID
        self.referencedFrameNumbers = referencedFrameNumbers
    }
}

/// Resolved frame geometry suitable for volume, MPR, and cine consumers.
public struct DicomFrameGeometry: Equatable, Sendable {
    public let frameIndex: Int
    public let imagePositionPatient: SIMD3<Double>?
    public let imageOrientationPatient: DicomPlaneOrientation?
    public let pixelMeasures: DicomPixelMeasures?
    public let frameContent: DicomFrameContent?
    public let sourceImageReferences: [DicomSourceImageReference]

    public init?(frameIndex: Int, functionalGroups: DicomFrameFunctionalGroups) {
        guard functionalGroups.planePosition != nil ||
              functionalGroups.planeOrientation != nil ||
              functionalGroups.pixelMeasures != nil ||
              functionalGroups.frameContent != nil ||
              functionalGroups.derivationImage != nil else {
            return nil
        }

        self.frameIndex = frameIndex
        self.imagePositionPatient = functionalGroups.planePosition?.imagePositionPatient
        self.imageOrientationPatient = functionalGroups.planeOrientation
        self.pixelMeasures = functionalGroups.pixelMeasures
        self.frameContent = functionalGroups.frameContent
        self.sourceImageReferences = functionalGroups.derivationImage?.sourceImages ?? []
    }

    public var positionAlongNormal: Double? {
        guard let position = imagePositionPatient,
              let normal = imageOrientationPatient?.normal else {
            return nil
        }
        return simd_dot(position, normal)
    }
}

enum DicomEnhancedMultiframeParser {
    static func makeFunctionalGroups(
        sharedItems: [DicomSequenceItem],
        perFrameItems: [DicomSequenceItem],
        declaredFrameCount: Int
    ) -> DicomEnhancedMultiframeFunctionalGroups? {
        guard !sharedItems.isEmpty || !perFrameItems.isEmpty else { return nil }
        return DicomEnhancedMultiframeFunctionalGroups(
            shared: sharedItems.first.map { functionalGroups(from: $0.dataSet) },
            perFrame: perFrameItems.map { functionalGroups(from: $0.dataSet) },
            declaredFrameCount: declaredFrameCount
        )
    }

    private static func functionalGroups(from dataSet: DicomDataSet) -> DicomFrameFunctionalGroups {
        DicomFrameFunctionalGroups(
            frameContent: dataSet.firstNestedDataSet(for: .frameContentSequence).flatMap(frameContent),
            pixelMeasures: dataSet.firstNestedDataSet(for: .pixelMeasuresSequence).flatMap(pixelMeasures),
            planePosition: dataSet.firstNestedDataSet(for: .planePositionSequence).flatMap(planePosition),
            planeOrientation: dataSet.firstNestedDataSet(for: .planeOrientationSequence).flatMap(planeOrientation),
            derivationImage: derivationImage(from: dataSet.sequenceItems(for: .derivationImageSequence)),
            pixelValueTransformation: dataSet.firstNestedDataSet(for: .pixelValueTransformationSequence)
                .flatMap(pixelValueTransformation)
        )
    }

    private static func pixelValueTransformation(from dataSet: DicomDataSet) -> DicomPixelValueTransformation? {
        let intercept = dataSet.decimalString(for: .rescaleIntercept)
        let slope = dataSet.decimalString(for: .rescaleSlope)
        guard intercept != nil || slope != nil else { return nil }
        return DicomPixelValueTransformation(
            rescaleIntercept: intercept ?? 0,
            rescaleSlope: slope ?? 1
        )
    }

    private static func frameContent(from dataSet: DicomDataSet) -> DicomFrameContent? {
        let dimensionIndexValues = dataSet.ints(for: .dimensionIndexValues)
        let stackID = dataSet.string(for: .stackID)
        let inStackPositionNumber = dataSet.int(for: .inStackPositionNumber)
        let temporalPositionIndex = dataSet.int(for: .temporalPositionIndex)
        let frameAcquisitionNumber = dataSet.int(for: .frameAcquisitionNumber)
        guard !dimensionIndexValues.isEmpty ||
              stackID != nil ||
              inStackPositionNumber != nil ||
              temporalPositionIndex != nil ||
              frameAcquisitionNumber != nil else {
            return nil
        }
        return DicomFrameContent(
            dimensionIndexValues: dimensionIndexValues,
            stackID: stackID,
            inStackPositionNumber: inStackPositionNumber,
            temporalPositionIndex: temporalPositionIndex,
            frameAcquisitionNumber: frameAcquisitionNumber
        )
    }

    private static func pixelMeasures(from dataSet: DicomDataSet) -> DicomPixelMeasures? {
        let spacing = dataSet.decimalStrings(for: .pixelSpacing)
        let pixelSpacing = spacing.count >= 2 ? SIMD2<Double>(spacing[0], spacing[1]) : nil
        let sliceThickness = dataSet.decimalString(for: .sliceThickness)
        let spacingBetweenSlices = dataSet.decimalString(for: .sliceSpacing)
        guard pixelSpacing != nil || sliceThickness != nil || spacingBetweenSlices != nil else {
            return nil
        }
        return DicomPixelMeasures(
            pixelSpacing: pixelSpacing,
            sliceThickness: sliceThickness,
            spacingBetweenSlices: spacingBetweenSlices
        )
    }

    private static func planePosition(from dataSet: DicomDataSet) -> DicomPlanePosition? {
        guard let position = vector3(from: dataSet.decimalStrings(for: .imagePositionPatient)) else {
            return nil
        }
        return DicomPlanePosition(imagePositionPatient: position)
    }

    private static func planeOrientation(from dataSet: DicomDataSet) -> DicomPlaneOrientation? {
        let values = dataSet.decimalStrings(for: .imageOrientationPatient)
        guard values.count >= 6 else { return nil }
        return DicomPlaneOrientation(
            row: SIMD3<Double>(values[0], values[1], values[2]),
            column: SIMD3<Double>(values[3], values[4], values[5])
        )
    }

    private static func derivationImage(from items: [DicomSequenceItem]) -> DicomDerivationImage? {
        let sources = items.flatMap { item in
            item.dataSet.sequenceItems(for: .sourceImageSequence).map(sourceImageReference)
        }
        return sources.isEmpty ? nil : DicomDerivationImage(sourceImages: sources)
    }

    private static func sourceImageReference(from item: DicomSequenceItem) -> DicomSourceImageReference {
        DicomSourceImageReference(
            referencedSOPClassUID: item.dataSet.string(for: .referencedSOPClassUID),
            referencedSOPInstanceUID: item.dataSet.string(for: .referencedSOPInstanceUID),
            referencedFrameNumbers: item.dataSet.ints(for: .referencedFrameNumber)
        )
    }

    private static func vector3(from values: [Double]) -> SIMD3<Double>? {
        guard values.count >= 3 else { return nil }
        return SIMD3<Double>(values[0], values[1], values[2])
    }
}

private extension DicomDataSet {
    func firstNestedDataSet(for tag: DicomTag) -> DicomDataSet? {
        sequenceItems(for: tag).first?.dataSet
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
