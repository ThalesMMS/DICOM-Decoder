import Foundation

public enum DicomPhotometricInterpretation: Equatable, Hashable, Sendable {
    case monochrome1
    case monochrome2
    case rgb
    case paletteColor
    case ybrFull
    case ybrFull422
    case unknown(String)

    public init(_ value: String) {
        let normalized = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
        switch normalized {
        case "MONOCHROME1":
            self = .monochrome1
        case "MONOCHROME2", "":
            self = .monochrome2
        case "RGB":
            self = .rgb
        case "PALETTE COLOR":
            self = .paletteColor
        case "YBR_FULL":
            self = .ybrFull
        case "YBR_FULL_422":
            self = .ybrFull422
        default:
            self = .unknown(normalized)
        }
    }

    public var rawValue: String {
        switch self {
        case .monochrome1:
            return "MONOCHROME1"
        case .monochrome2:
            return "MONOCHROME2"
        case .rgb:
            return "RGB"
        case .paletteColor:
            return "PALETTE COLOR"
        case .ybrFull:
            return "YBR_FULL"
        case .ybrFull422:
            return "YBR_FULL_422"
        case .unknown(let value):
            return value
        }
    }
}

public struct DicomPaletteColorLookupTable: Equatable, Sendable {
    public let redDescriptor: DicomLUTDescriptor
    public let greenDescriptor: DicomLUTDescriptor
    public let blueDescriptor: DicomLUTDescriptor
    public let red: [UInt8]
    public let green: [UInt8]
    public let blue: [UInt8]

    public init(redDescriptor: DicomLUTDescriptor,
                greenDescriptor: DicomLUTDescriptor,
                blueDescriptor: DicomLUTDescriptor,
                red: [UInt8],
                green: [UInt8],
                blue: [UInt8]) {
        self.redDescriptor = redDescriptor
        self.greenDescriptor = greenDescriptor
        self.blueDescriptor = blueDescriptor
        self.red = red
        self.green = green
        self.blue = blue
    }
}

public struct DicomNativeColorMetadata: Equatable, Sendable {
    public let photometricInterpretation: DicomPhotometricInterpretation
    public let samplesPerPixel: Int
    public let planarConfiguration: Int?
    public let bitsAllocated: Int
    public let bitsStored: Int
    public let highBit: Int
    public let pixelRepresentation: Int
    public let paletteColorLookupTable: DicomPaletteColorLookupTable?
    public let iccProfile: Data?

    public init(photometricInterpretation: DicomPhotometricInterpretation,
                samplesPerPixel: Int,
                planarConfiguration: Int?,
                bitsAllocated: Int,
                bitsStored: Int,
                highBit: Int,
                pixelRepresentation: Int,
                paletteColorLookupTable: DicomPaletteColorLookupTable?,
                iccProfile: Data?) {
        self.photometricInterpretation = photometricInterpretation
        self.samplesPerPixel = samplesPerPixel
        self.planarConfiguration = planarConfiguration
        self.bitsAllocated = bitsAllocated
        self.bitsStored = bitsStored
        self.highBit = highBit
        self.pixelRepresentation = pixelRepresentation
        self.paletteColorLookupTable = paletteColorLookupTable
        self.iccProfile = iccProfile
    }

    public static let empty = DicomNativeColorMetadata(
        photometricInterpretation: .monochrome2,
        samplesPerPixel: 0,
        planarConfiguration: nil,
        bitsAllocated: 0,
        bitsStored: 0,
        highBit: 0,
        pixelRepresentation: 0,
        paletteColorLookupTable: nil,
        iccProfile: nil
    )
}

public struct DicomDisplayPixelBuffer: Equatable, Sendable {
    public let width: Int
    public let height: Int
    public let frameIndex: Int
    public let photometricInterpretation: DicomPhotometricInterpretation
    public let rgbData: Data
    public let iccProfile: Data?

    public var bytesPerPixel: Int { 3 }

    public init(width: Int,
                height: Int,
                frameIndex: Int,
                photometricInterpretation: DicomPhotometricInterpretation,
                rgbData: Data,
                iccProfile: Data?) {
        self.width = width
        self.height = height
        self.frameIndex = frameIndex
        self.photometricInterpretation = photometricInterpretation
        self.rgbData = rgbData
        self.iccProfile = iccProfile
    }
}

public enum DicomColorConversionError: Error, Equatable, LocalizedError, Sendable {
    case missingPixelDataFrame(Int)
    case unsupportedPhotometricInterpretation(String)
    case unsupportedSamplesPerPixel(Int)
    case unsupportedBitsAllocated(Int)
    case unsupportedPlanarConfiguration(Int?)
    case missingPaletteColorLookupTable
    case invalidPixelData(String)

    public var errorDescription: String? {
        switch self {
        case .missingPixelDataFrame(let frame):
            return "Missing native Pixel Data frame \(frame)."
        case .unsupportedPhotometricInterpretation(let value):
            return "Unsupported Photometric Interpretation: \(value)."
        case .unsupportedSamplesPerPixel(let value):
            return "Unsupported Samples per Pixel: \(value)."
        case .unsupportedBitsAllocated(let value):
            return "Unsupported Bits Allocated for color conversion: \(value)."
        case .unsupportedPlanarConfiguration(let value):
            let text = value.map(String.init) ?? "absent"
            return "Unsupported Planar Configuration: \(text)."
        case .missingPaletteColorLookupTable:
            return "PALETTE COLOR conversion requires red, green, and blue lookup tables."
        case .invalidPixelData(let reason):
            return "Invalid Pixel Data: \(reason)."
        }
    }
}

extension DCMDecoder {
    public var nativeColorMetadata: DicomNativeColorMetadata {
        synchronized {
            let descriptor = pixelDataDescriptor
            return makeNativeColorMetadataUnsafe(descriptor: descriptor)
        }
    }

    public func displayRGBPixelBuffer(frame frameIndex: Int = 0) throws -> DicomDisplayPixelBuffer {
        try synchronized {
            guard let descriptor = pixelDataDescriptor,
                  let frame = getFrame(frameIndex) else {
                throw DicomColorConversionError.missingPixelDataFrame(frameIndex)
            }

            let metadata = makeNativeColorMetadataUnsafe(descriptor: descriptor)
            let rgbData: Data
            switch metadata.photometricInterpretation {
            case .monochrome1, .monochrome2:
                rgbData = try makeMonochromeDisplayRGB(frame: frame, metadata: metadata)
            case .rgb:
                rgbData = try makeRGBDisplayData(frame: frame)
            case .paletteColor:
                rgbData = try makePaletteDisplayRGB(frame: frame, metadata: metadata)
            case .ybrFull:
                rgbData = try makeYBRFullDisplayRGB(frame: frame)
            case .ybrFull422:
                rgbData = try makeYBRFull422DisplayRGB(frame: frame)
            case .unknown(let value):
                throw DicomColorConversionError.unsupportedPhotometricInterpretation(value)
            }

            return DicomDisplayPixelBuffer(
                width: descriptor.columns,
                height: descriptor.rows,
                frameIndex: frameIndex,
                photometricInterpretation: metadata.photometricInterpretation,
                rgbData: rgbData,
                iccProfile: metadata.iccProfile
            )
        }
    }

    private func makeNativeColorMetadataUnsafe(
        descriptor: DicomPixelDataDescriptor?
    ) -> DicomNativeColorMetadata {
        let photometric = descriptor?.photometricInterpretation
            ?? (photometricInterpretation.isEmpty ? "MONOCHROME2" : photometricInterpretation)
        let dataSet = self.dataSet
        return DicomNativeColorMetadata(
            photometricInterpretation: DicomPhotometricInterpretation(photometric),
            samplesPerPixel: descriptor?.samplesPerPixel ?? samplesPerPixel,
            planarConfiguration: descriptor?.planarConfiguration ?? intValue(for: .planarConfiguration),
            bitsAllocated: descriptor?.bitsAllocated ?? bitDepth,
            bitsStored: descriptor?.bitsStored ?? intValue(for: .bitsStored) ?? bitDepth,
            highBit: descriptor?.highBit ?? intValue(for: .highBit) ?? max(0, bitDepth - 1),
            pixelRepresentation: descriptor?.pixelRepresentation ?? pixelRepresentation,
            paletteColorLookupTable: makePaletteColorLookupTableUnsafe(),
            iccProfile: dataSet.element(for: .iccProfile)?.bytesValue
        )
    }

    private func makePaletteColorLookupTableUnsafe() -> DicomPaletteColorLookupTable? {
        guard let reds, let greens, let blues else {
            return nil
        }

        let count = min(reds.count, greens.count, blues.count)
        guard count > 0 else { return nil }
        let defaultDescriptor = DicomLUTDescriptor(
            storedEntryCount: count,
            firstMappedValue: 0,
            bitsPerEntry: 8
        )!

        return DicomPaletteColorLookupTable(
            redDescriptor: redPaletteDescriptor ?? defaultDescriptor,
            greenDescriptor: greenPaletteDescriptor ?? defaultDescriptor,
            blueDescriptor: bluePaletteDescriptor ?? defaultDescriptor,
            red: Array(reds.prefix(count)),
            green: Array(greens.prefix(count)),
            blue: Array(blues.prefix(count))
        )
    }

    private func makeMonochromeDisplayRGB(
        frame: DicomPixelFrame,
        metadata: DicomNativeColorMetadata
    ) throws -> Data {
        guard frame.descriptor.samplesPerPixel == 1 else {
            throw DicomColorConversionError.unsupportedSamplesPerPixel(frame.descriptor.samplesPerPixel)
        }
        guard frame.descriptor.bytesPerSample <= 2 else {
            throw DicomColorConversionError.unsupportedBitsAllocated(frame.descriptor.bitsAllocated)
        }

        let pixelsPerFrame = frame.descriptor.rows * frame.descriptor.columns
        let profile = displayTransformProfile
        var output = [UInt8](repeating: 0, count: pixelsPerFrame * 3)

        for pixelIndex in 0..<pixelsPerFrame {
            guard let storedValue = storedSampleValue(
                frameData: frame.data,
                pixelIndex: pixelIndex,
                sample: 0,
                descriptor: frame.descriptor
            ) else {
                throw DicomColorConversionError.invalidPixelData("Missing monochrome sample at pixel \(pixelIndex).")
            }

            let fallback = scaledDisplayByte(storedValue: storedValue, metadata: metadata)
            let gray = profile.displayValue(forStoredPixelValue: Double(storedValue)) ?? fallback
            let base = pixelIndex * 3
            output[base] = gray
            output[base + 1] = gray
            output[base + 2] = gray
        }

        return Data(output)
    }

    private func makeRGBDisplayData(frame: DicomPixelFrame) throws -> Data {
        try validateThreeSample8BitFrame(frame)
        return try makeThreeSampleDisplayRGB(frame: frame) { red, green, blue in
            (red, green, blue)
        }
    }

    private func makeYBRFullDisplayRGB(frame: DicomPixelFrame) throws -> Data {
        try validateThreeSample8BitFrame(frame)
        return try makeThreeSampleDisplayRGB(frame: frame) { y, cb, cr in
            Self.ybrToRgb(y: y, cb: cb, cr: cr)
        }
    }

    private func makeYBRFull422DisplayRGB(frame: DicomPixelFrame) throws -> Data {
        let descriptor = frame.descriptor
        guard descriptor.samplesPerPixel == 3 else {
            throw DicomColorConversionError.unsupportedSamplesPerPixel(descriptor.samplesPerPixel)
        }
        guard descriptor.bitsAllocated == 8 else {
            throw DicomColorConversionError.unsupportedBitsAllocated(descriptor.bitsAllocated)
        }
        guard descriptor.planarConfiguration == nil || descriptor.planarConfiguration == 0 else {
            throw DicomColorConversionError.unsupportedPlanarConfiguration(descriptor.planarConfiguration)
        }
        guard descriptor.columns % 2 == 0 else {
            throw DicomColorConversionError.invalidPixelData("YBR_FULL_422 requires an even column count.")
        }

        let pixelsPerFrame = descriptor.rows * descriptor.columns
        let expectedBytes = descriptor.rows * (descriptor.columns / 2) * 4
        guard frame.data.count >= expectedBytes else {
            throw DicomColorConversionError.invalidPixelData("YBR_FULL_422 frame is shorter than expected.")
        }

        var output = [UInt8](repeating: 0, count: pixelsPerFrame * 3)
        var inputOffset = 0
        for row in 0..<descriptor.rows {
            for columnPair in stride(from: 0, to: descriptor.columns, by: 2) {
                let y1 = frame.data[inputOffset]
                let y2 = frame.data[inputOffset + 1]
                let cb = frame.data[inputOffset + 2]
                let cr = frame.data[inputOffset + 3]
                inputOffset += 4

                let pixelIndex = row * descriptor.columns + columnPair
                writeRGB(Self.ybrToRgb(y: y1, cb: cb, cr: cr), to: &output, pixelIndex: pixelIndex)
                writeRGB(Self.ybrToRgb(y: y2, cb: cb, cr: cr), to: &output, pixelIndex: pixelIndex + 1)
            }
        }

        return Data(output)
    }

    private func makePaletteDisplayRGB(
        frame: DicomPixelFrame,
        metadata: DicomNativeColorMetadata
    ) throws -> Data {
        let descriptor = frame.descriptor
        guard descriptor.samplesPerPixel == 1 else {
            throw DicomColorConversionError.unsupportedSamplesPerPixel(descriptor.samplesPerPixel)
        }
        guard descriptor.bytesPerSample <= 2 else {
            throw DicomColorConversionError.unsupportedBitsAllocated(descriptor.bitsAllocated)
        }
        guard let palette = metadata.paletteColorLookupTable else {
            throw DicomColorConversionError.missingPaletteColorLookupTable
        }

        let pixelsPerFrame = descriptor.rows * descriptor.columns
        var output = [UInt8](repeating: 0, count: pixelsPerFrame * 3)

        for pixelIndex in 0..<pixelsPerFrame {
            guard let storedValue = storedSampleValue(
                frameData: frame.data,
                pixelIndex: pixelIndex,
                sample: 0,
                descriptor: descriptor
            ) else {
                throw DicomColorConversionError.invalidPixelData("Missing palette index at pixel \(pixelIndex).")
            }
            guard let redIndex = palette.redDescriptor.clampedIndex(
                for: storedValue,
                availableEntryCount: palette.red.count
            ),
                  let greenIndex = palette.greenDescriptor.clampedIndex(
                    for: storedValue,
                    availableEntryCount: palette.green.count
                  ),
                  let blueIndex = palette.blueDescriptor.clampedIndex(
                    for: storedValue,
                    availableEntryCount: palette.blue.count
                  ) else {
                throw DicomColorConversionError.missingPaletteColorLookupTable
            }

            let base = pixelIndex * 3
            output[base] = palette.red[redIndex]
            output[base + 1] = palette.green[greenIndex]
            output[base + 2] = palette.blue[blueIndex]
        }

        return Data(output)
    }

    private func validateThreeSample8BitFrame(_ frame: DicomPixelFrame) throws {
        let descriptor = frame.descriptor
        guard descriptor.samplesPerPixel == 3 else {
            throw DicomColorConversionError.unsupportedSamplesPerPixel(descriptor.samplesPerPixel)
        }
        guard descriptor.bitsAllocated == 8 else {
            throw DicomColorConversionError.unsupportedBitsAllocated(descriptor.bitsAllocated)
        }
        guard descriptor.planarConfiguration == nil
                || descriptor.planarConfiguration == 0
                || descriptor.planarConfiguration == 1 else {
            throw DicomColorConversionError.unsupportedPlanarConfiguration(descriptor.planarConfiguration)
        }
    }

    private func makeThreeSampleDisplayRGB(
        frame: DicomPixelFrame,
        transform: (UInt8, UInt8, UInt8) -> (UInt8, UInt8, UInt8)
    ) throws -> Data {
        let descriptor = frame.descriptor
        let pixelsPerFrame = descriptor.rows * descriptor.columns
        var output = [UInt8](repeating: 0, count: pixelsPerFrame * 3)

        for pixelIndex in 0..<pixelsPerFrame {
            guard let first = storedSampleValue(
                frameData: frame.data,
                pixelIndex: pixelIndex,
                sample: 0,
                descriptor: descriptor
            ),
                  let second = storedSampleValue(
                    frameData: frame.data,
                    pixelIndex: pixelIndex,
                    sample: 1,
                    descriptor: descriptor
                  ),
                  let third = storedSampleValue(
                    frameData: frame.data,
                    pixelIndex: pixelIndex,
                    sample: 2,
                    descriptor: descriptor
                  ) else {
                throw DicomColorConversionError.invalidPixelData("Missing RGB/YBR sample at pixel \(pixelIndex).")
            }

            let rgb = transform(UInt8(clamping: first), UInt8(clamping: second), UInt8(clamping: third))
            writeRGB(rgb, to: &output, pixelIndex: pixelIndex)
        }

        return Data(output)
    }

    private func storedSampleValue(
        frameData: Data,
        pixelIndex: Int,
        sample: Int,
        descriptor: DicomPixelDataDescriptor
    ) -> Int? {
        guard pixelIndex >= 0,
              sample >= 0,
              sample < descriptor.samplesPerPixel,
              descriptor.bytesPerSample <= 2 else {
            return nil
        }

        let pixelsPerFrame = descriptor.rows * descriptor.columns
        guard pixelIndex < pixelsPerFrame else { return nil }

        let sampleIndex: Int
        if descriptor.planarConfiguration == 1 && descriptor.samplesPerPixel > 1 {
            sampleIndex = sample * pixelsPerFrame + pixelIndex
        } else {
            sampleIndex = pixelIndex * descriptor.samplesPerPixel + sample
        }

        let byteOffset = sampleIndex * descriptor.bytesPerSample
        guard byteOffset >= 0,
              byteOffset + descriptor.bytesPerSample <= frameData.count else {
            return nil
        }

        let rawValue: Int
        switch descriptor.bytesPerSample {
        case 1:
            rawValue = Int(frameData[byteOffset])
        case 2:
            rawValue = Int(frameData.readUInt16(at: byteOffset, littleEndian: currentLittleEndian()))
        default:
            return nil
        }

        let shift = max(0, descriptor.highBit - descriptor.bitsStored + 1)
        let mask = (1 << descriptor.bitsStored) - 1
        let storedBits = (rawValue >> shift) & mask

        guard descriptor.isSigned else {
            return storedBits
        }

        let signBit = 1 << (descriptor.bitsStored - 1)
        return (storedBits & signBit) != 0
            ? storedBits - (1 << descriptor.bitsStored)
            : storedBits
    }

    private func scaledDisplayByte(
        storedValue: Int,
        metadata: DicomNativeColorMetadata
    ) -> UInt8 {
        let maximum = max(1, (1 << min(max(metadata.bitsStored, 1), 16)) - 1)
        let normalized = Double(max(0, min(maximum, storedValue))) / Double(maximum)
        let display = metadata.photometricInterpretation == .monochrome1 ? 1.0 - normalized : normalized
        return UInt8(max(0, min(255, Int((display * 255.0).rounded()))))
    }

    private func writeRGB(
        _ rgb: (UInt8, UInt8, UInt8),
        to output: inout [UInt8],
        pixelIndex: Int
    ) {
        let base = pixelIndex * 3
        output[base] = rgb.0
        output[base + 1] = rgb.1
        output[base + 2] = rgb.2
    }

    private static func ybrToRgb(y: UInt8, cb: UInt8, cr: UInt8) -> (UInt8, UInt8, UInt8) {
        let luminance = Double(y)
        let cbShift = Double(cb) - 128.0
        let crShift = Double(cr) - 128.0
        let red = luminance + 1.402 * crShift
        let green = luminance - 0.344136 * cbShift - 0.714136 * crShift
        let blue = luminance + 1.772 * cbShift
        return (clampedByte(red), clampedByte(green), clampedByte(blue))
    }

    private static func clampedByte(_ value: Double) -> UInt8 {
        UInt8(max(0, min(255, Int(value.rounded()))))
    }
}

public extension DicomDecoderProtocol {
    var nativeColorMetadata: DicomNativeColorMetadata {
        .empty
    }

    func displayRGBPixelBuffer(frame: Int) throws -> DicomDisplayPixelBuffer {
        throw DicomColorConversionError.unsupportedPhotometricInterpretation(photometricInterpretation)
    }

    func displayRGBPixelBuffer() throws -> DicomDisplayPixelBuffer {
        try displayRGBPixelBuffer(frame: 0)
    }
}

private extension Data {
    func readUInt16(at offset: Int, littleEndian: Bool) -> UInt16 {
        let b0 = UInt16(self[offset])
        let b1 = UInt16(self[offset + 1])
        return littleEndian ? (b1 << 8 | b0) : (b0 << 8 | b1)
    }
}
