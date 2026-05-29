import Foundation

/// Native uncompressed Pixel Data layout for frame-addressable access.
public struct DicomPixelDataDescriptor: Equatable, Sendable {
    /// DICOM Rows (0028,0010).
    public let rows: Int
    /// DICOM Columns (0028,0011).
    public let columns: Int
    /// Number of frames, defaulting to one when Number of Frames is absent.
    public let numberOfFrames: Int
    /// Bits Allocated (0028,0100).
    public let bitsAllocated: Int
    /// Bits Stored (0028,0101).
    public let bitsStored: Int
    /// High Bit (0028,0102).
    public let highBit: Int
    /// Pixel Representation (0028,0103), where 1 means signed samples.
    public let pixelRepresentation: Int
    /// Samples per Pixel (0028,0002).
    public let samplesPerPixel: Int
    /// Planar Configuration (0028,0006), when present.
    public let planarConfiguration: Int?
    /// Photometric Interpretation (0028,0004).
    public let photometricInterpretation: String
    /// Absolute byte offset where native Pixel Data begins in the loaded file.
    public let pixelDataOffset: Int
    /// Whole bytes used by each stored sample.
    public let bytesPerSample: Int
    /// Byte count for one complete frame.
    public let bytesPerFrame: Int
    /// Byte count for all complete frames.
    public let totalPixelBytes: Int
    /// Absolute byte offset of each frame in the loaded file.
    public let frameOffsets: [Int]

    public init?(rows: Int,
                 columns: Int,
                 numberOfFrames: Int,
                 bitsAllocated: Int,
                 bitsStored: Int,
                 highBit: Int,
                 pixelRepresentation: Int,
                 samplesPerPixel: Int,
                 planarConfiguration: Int?,
                 photometricInterpretation: String,
                 pixelDataOffset: Int) {
        guard rows > 0,
              columns > 0,
              numberOfFrames > 0,
              bitsAllocated > 0,
              bitsStored > 0,
              highBit >= 0,
              samplesPerPixel > 0,
              pixelDataOffset >= 0 else {
            return nil
        }

        let bytesPerSample = max(1, (bitsAllocated + 7) / 8)
        let pixelsPerFrame = rows.multipliedReportingOverflow(by: columns)
        guard !pixelsPerFrame.overflow else { return nil }

        let samplesPerFrame = pixelsPerFrame.partialValue.multipliedReportingOverflow(by: samplesPerPixel)
        guard !samplesPerFrame.overflow else { return nil }

        let bytesPerFrameValue: Int
        if photometricInterpretation
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased() == "YBR_FULL_422",
           samplesPerPixel == 3 {
            let pairsPerRow = (columns + 1) / 2
            let bytesPerPair = 4.multipliedReportingOverflow(by: bytesPerSample)
            guard !bytesPerPair.overflow else { return nil }
            let bytesPerRow = pairsPerRow.multipliedReportingOverflow(by: bytesPerPair.partialValue)
            guard !bytesPerRow.overflow else { return nil }
            let bytesPerFrame = rows.multipliedReportingOverflow(by: bytesPerRow.partialValue)
            guard !bytesPerFrame.overflow else { return nil }
            bytesPerFrameValue = bytesPerFrame.partialValue
        } else {
            let bytesPerFrame = samplesPerFrame.partialValue.multipliedReportingOverflow(by: bytesPerSample)
            guard !bytesPerFrame.overflow else { return nil }
            bytesPerFrameValue = bytesPerFrame.partialValue
        }

        let totalPixelBytes = bytesPerFrameValue.multipliedReportingOverflow(by: numberOfFrames)
        guard !totalPixelBytes.overflow else { return nil }

        var frameOffsets: [Int] = []
        frameOffsets.reserveCapacity(numberOfFrames)
        for frameIndex in 0..<numberOfFrames {
            let offsetDelta = bytesPerFrameValue.multipliedReportingOverflow(by: frameIndex)
            guard !offsetDelta.overflow else { return nil }
            let frameOffset = pixelDataOffset.addingReportingOverflow(offsetDelta.partialValue)
            guard !frameOffset.overflow else { return nil }
            frameOffsets.append(frameOffset.partialValue)
        }

        self.rows = rows
        self.columns = columns
        self.numberOfFrames = numberOfFrames
        self.bitsAllocated = bitsAllocated
        self.bitsStored = bitsStored
        self.highBit = highBit
        self.pixelRepresentation = pixelRepresentation
        self.samplesPerPixel = samplesPerPixel
        self.planarConfiguration = planarConfiguration
        self.photometricInterpretation = photometricInterpretation
        self.pixelDataOffset = pixelDataOffset
        self.bytesPerSample = bytesPerSample
        self.bytesPerFrame = bytesPerFrameValue
        self.totalPixelBytes = totalPixelBytes.partialValue
        self.frameOffsets = frameOffsets
    }

    public var isSigned: Bool {
        pixelRepresentation == 1
    }

    public var isMultiFrame: Bool {
        numberOfFrames > 1
    }

    /// Returns the absolute byte range for a zero-based frame index.
    public func byteRange(forFrame index: Int) -> Range<Int>? {
        guard index >= 0, index < numberOfFrames else { return nil }
        let start = frameOffsets[index]
        let end = start.addingReportingOverflow(bytesPerFrame)
        guard !end.overflow else { return nil }
        return start..<end.partialValue
    }

    /// Returns the contiguous absolute byte range for a zero-based frame range.
    public func byteRange(forFrames range: Range<Int>) -> Range<Int>? {
        guard range.lowerBound >= 0,
              range.lowerBound < range.upperBound,
              range.upperBound <= numberOfFrames,
              let firstFrameRange = byteRange(forFrame: range.lowerBound),
              let lastFrameRange = byteRange(forFrame: range.upperBound - 1) else {
            return nil
        }
        return firstFrameRange.lowerBound..<lastFrameRange.upperBound
    }
}

/// Raw native bytes for one uncompressed Pixel Data frame.
public struct DicomPixelFrame: Equatable, Sendable {
    /// Zero-based frame index.
    public let index: Int
    /// Absolute byte range copied from the source file.
    public let byteRange: Range<Int>
    /// Raw native frame bytes.
    public let data: Data
    /// Descriptor used to derive the frame layout.
    public let descriptor: DicomPixelDataDescriptor

    public init(index: Int,
                byteRange: Range<Int>,
                data: Data,
                descriptor: DicomPixelDataDescriptor) {
        self.index = index
        self.byteRange = byteRange
        self.data = data
        self.descriptor = descriptor
    }
}
