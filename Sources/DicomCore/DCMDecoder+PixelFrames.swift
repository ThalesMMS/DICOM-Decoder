import Foundation

extension DCMDecoder {
    public var pixelDataDescriptor: DicomPixelDataDescriptor? {
        synchronized {
            makePixelDataDescriptorUnsafe()
        }
    }

    public func getFrame(_ index: Int) -> DicomPixelFrame? {
        synchronized {
            guard let descriptor = makePixelDataDescriptorUnsafe(),
                  let byteRange = descriptor.byteRange(forFrame: index),
                  byteRange.upperBound <= dicomData.count else {
                return nil
            }

            return DicomPixelFrame(
                index: index,
                byteRange: byteRange,
                data: Data(dicomData[byteRange]),
                descriptor: descriptor
            )
        }
    }

    public func getFrames(_ range: Range<Int>) -> [DicomPixelFrame]? {
        synchronized {
            guard let descriptor = makePixelDataDescriptorUnsafe(),
                  range.lowerBound >= 0,
                  range.lowerBound < range.upperBound,
                  range.upperBound <= descriptor.numberOfFrames else {
                return nil
            }
            return makeFramesUnsafe(descriptor: descriptor, range: range)
        }
    }

    public func getAllFrames() -> [DicomPixelFrame]? {
        synchronized {
            guard let descriptor = makePixelDataDescriptorUnsafe() else {
                return nil
            }
            return makeFramesUnsafe(descriptor: descriptor, range: 0..<descriptor.numberOfFrames)
        }
    }

    private func makePixelDataDescriptorUnsafe() -> DicomPixelDataDescriptor? {
        guard dicomFound,
              !compressedImage,
              offset >= 0 else {
            return nil
        }

        let rows = height
        let columns = width
        let frames = max(1, nImages)
        let bitsAllocated = bitDepth
        let bitsStored = intValue(for: DicomTag.bitsStored.rawValue) ?? bitsAllocated
        let highBit = intValue(for: DicomTag.highBit.rawValue) ?? max(0, bitsStored - 1)
        let planarConfiguration = intValue(for: DicomTag.planarConfiguration.rawValue)
        let photometric = photometricInterpretation.isEmpty ? "MONOCHROME2" : photometricInterpretation

        guard let descriptor = DicomPixelDataDescriptor(
            rows: rows,
            columns: columns,
            numberOfFrames: frames,
            bitsAllocated: bitsAllocated,
            bitsStored: bitsStored,
            highBit: highBit,
            pixelRepresentation: pixelRepresentation,
            samplesPerPixel: samplesPerPixel,
            planarConfiguration: planarConfiguration,
            photometricInterpretation: photometric,
            pixelDataOffset: offset
        ) else {
            return nil
        }

        let endOffset = descriptor.pixelDataOffset.addingReportingOverflow(descriptor.totalPixelBytes)
        guard !endOffset.overflow,
              endOffset.partialValue <= dicomData.count else {
            return nil
        }

        return descriptor
    }

    private func makeFramesUnsafe(
        descriptor: DicomPixelDataDescriptor,
        range: Range<Int>
    ) -> [DicomPixelFrame]? {
        var frames: [DicomPixelFrame] = []
        frames.reserveCapacity(range.count)
        for index in range {
            guard let byteRange = descriptor.byteRange(forFrame: index),
                  byteRange.upperBound <= dicomData.count else {
                return nil
            }
            frames.append(DicomPixelFrame(
                index: index,
                byteRange: byteRange,
                data: Data(dicomData[byteRange]),
                descriptor: descriptor
            ))
        }
        return frames
    }
}
