import XCTest
@testable import DicomCore

final class DicomColorPixelDataTests: XCTestCase {
    func testRGBInterleavedAndICCProfileExposeDisplayBufferAndMetadata() throws {
        let iccProfile = Data([0x01, 0x02, 0x03, 0x04])
        let pixelBytes: [UInt8] = [255, 0, 0, 0, 128, 255]
        let url = try makeTemporaryDICOM(
            photometricInterpretation: "RGB",
            samplesPerPixel: 3,
            planarConfiguration: 0,
            width: 2,
            height: 1,
            bitsAllocated: 8,
            pixelBytes: pixelBytes,
            iccProfile: iccProfile
        )
        defer { try? FileManager.default.removeItem(at: url) }

        let decoder = try DCMDecoder(contentsOf: url)
        let metadata = decoder.nativeColorMetadata

        XCTAssertEqual(metadata.photometricInterpretation, .rgb)
        XCTAssertEqual(metadata.samplesPerPixel, 3)
        XCTAssertEqual(metadata.planarConfiguration, 0)
        XCTAssertEqual(metadata.iccProfile, iccProfile)

        let display = try decoder.displayRGBPixelBuffer()
        XCTAssertEqual(display.width, 2)
        XCTAssertEqual(display.height, 1)
        XCTAssertEqual(display.bytesPerPixel, 3)
        XCTAssertEqual(display.rgbData, Data(pixelBytes))
        XCTAssertEqual(display.iccProfile, iccProfile)
    }

    func testRGBPlanarConvertsToInterleavedDisplayBuffer() throws {
        let pixelBytes: [UInt8] = [10, 40, 20, 50, 30, 60]
        let url = try makeTemporaryDICOM(
            photometricInterpretation: "RGB",
            samplesPerPixel: 3,
            planarConfiguration: 1,
            width: 2,
            height: 1,
            bitsAllocated: 8,
            pixelBytes: pixelBytes
        )
        defer { try? FileManager.default.removeItem(at: url) }

        let decoder = try DCMDecoder(contentsOf: url)
        let display = try decoder.displayRGBPixelBuffer()

        XCTAssertEqual(display.rgbData, Data([10, 20, 30, 40, 50, 60]))
    }

    func testPaletteColorConvertsToRGBUsingLookupTables() throws {
        let url = try makeTemporaryDICOM(
            photometricInterpretation: "PALETTE COLOR",
            samplesPerPixel: 1,
            width: 3,
            height: 1,
            bitsAllocated: 8,
            pixelBytes: [0, 1, 2],
            paletteDescriptor: [3, 0, 16],
            redPalette: [0x0000, 0x8000, 0xFFFF],
            greenPalette: [0xFFFF, 0x0000, 0x8000],
            bluePalette: [0x0000, 0xFFFF, 0x8000]
        )
        defer { try? FileManager.default.removeItem(at: url) }

        let decoder = try DCMDecoder(contentsOf: url)
        let metadata = decoder.nativeColorMetadata
        let palette = try XCTUnwrap(metadata.paletteColorLookupTable)

        XCTAssertEqual(metadata.photometricInterpretation, .paletteColor)
        XCTAssertEqual(palette.redDescriptor.entryCount, 3)
        XCTAssertEqual(palette.redDescriptor.firstMappedValue, 0)
        XCTAssertEqual(palette.redDescriptor.bitsPerEntry, 16)
        XCTAssertEqual(palette.red, [0, 128, 255])
        XCTAssertEqual(palette.green, [255, 0, 128])
        XCTAssertEqual(palette.blue, [0, 255, 128])

        let display = try decoder.displayRGBPixelBuffer()
        XCTAssertEqual(display.rgbData, Data([
            0, 255, 0,
            128, 0, 255,
            255, 128, 128
        ]))
    }

    func testYBRFullConvertsToRGB() throws {
        let pixelBytes: [UInt8] = [
            128, 128, 128,
            76, 85, 255
        ]
        let url = try makeTemporaryDICOM(
            photometricInterpretation: "YBR_FULL",
            samplesPerPixel: 3,
            planarConfiguration: 0,
            width: 2,
            height: 1,
            bitsAllocated: 8,
            pixelBytes: pixelBytes
        )
        defer { try? FileManager.default.removeItem(at: url) }

        let decoder = try DCMDecoder(contentsOf: url)
        let display = try decoder.displayRGBPixelBuffer()

        XCTAssertEqual(display.rgbData, Data([
            128, 128, 128,
            254, 0, 0
        ]))
    }

    func testYBRFull422UsesSubsampledFrameLayoutAndConvertsToRGB() throws {
        let pixelBytes: [UInt8] = [10, 20, 128, 128]
        let url = try makeTemporaryDICOM(
            photometricInterpretation: "YBR_FULL_422",
            samplesPerPixel: 3,
            planarConfiguration: 0,
            width: 2,
            height: 1,
            bitsAllocated: 8,
            pixelBytes: pixelBytes
        )
        defer { try? FileManager.default.removeItem(at: url) }

        let decoder = try DCMDecoder(contentsOf: url)
        let descriptor = try XCTUnwrap(decoder.pixelDataDescriptor)
        let display = try decoder.displayRGBPixelBuffer()

        XCTAssertEqual(descriptor.bytesPerFrame, 4)
        XCTAssertEqual(descriptor.totalPixelBytes, 4)
        XCTAssertEqual(display.rgbData, Data([
            10, 10, 10,
            20, 20, 20
        ]))
    }

    func testUnsupportedColorCombinationThrowsDocumentedError() throws {
        let url = try makeTemporaryDICOM(
            photometricInterpretation: "RGB",
            samplesPerPixel: 3,
            planarConfiguration: 0,
            width: 1,
            height: 1,
            bitsAllocated: 16,
            pixelBytes: [0, 0, 0, 0, 0, 0]
        )
        defer { try? FileManager.default.removeItem(at: url) }

        let decoder = try DCMDecoder(contentsOf: url)

        XCTAssertThrowsError(try decoder.displayRGBPixelBuffer()) { error in
            XCTAssertEqual(error as? DicomColorConversionError, .unsupportedBitsAllocated(16))
        }
    }

    private func makeTemporaryDICOM(
        photometricInterpretation: String,
        samplesPerPixel: UInt16,
        planarConfiguration: UInt16? = nil,
        width: UInt16,
        height: UInt16,
        bitsAllocated: UInt16,
        pixelBytes: [UInt8],
        paletteDescriptor: [UInt16]? = nil,
        redPalette: [UInt16]? = nil,
        greenPalette: [UInt16]? = nil,
        bluePalette: [UInt16]? = nil,
        iccProfile: Data? = nil
    ) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("color_pixel_\(UUID().uuidString).dcm")
        var data = Data()
        data.append(Data(count: 128))
        data.append(contentsOf: "DICM".utf8)

        appendUS(&data, group: 0x0028, element: 0x0010, value: height)
        appendUS(&data, group: 0x0028, element: 0x0011, value: width)
        appendUS(&data, group: 0x0028, element: 0x0002, value: samplesPerPixel)
        appendCS(&data, group: 0x0028, element: 0x0004, value: photometricInterpretation)
        if let planarConfiguration {
            appendUS(&data, group: 0x0028, element: 0x0006, value: planarConfiguration)
        }
        appendUS(&data, group: 0x0028, element: 0x0100, value: bitsAllocated)
        appendUS(&data, group: 0x0028, element: 0x0101, value: bitsAllocated)
        appendUS(&data, group: 0x0028, element: 0x0102, value: bitsAllocated - 1)
        appendUS(&data, group: 0x0028, element: 0x0103, value: 0)

        if let paletteDescriptor {
            appendUSValues(&data, group: 0x0028, element: 0x1101, values: paletteDescriptor)
            appendUSValues(&data, group: 0x0028, element: 0x1102, values: paletteDescriptor)
            appendUSValues(&data, group: 0x0028, element: 0x1103, values: paletteDescriptor)
        }
        if let redPalette {
            appendOWValues(&data, group: 0x0028, element: 0x1201, values: redPalette)
        }
        if let greenPalette {
            appendOWValues(&data, group: 0x0028, element: 0x1202, values: greenPalette)
        }
        if let bluePalette {
            appendOWValues(&data, group: 0x0028, element: 0x1203, values: bluePalette)
        }
        if let iccProfile {
            appendBinary(&data, group: 0x0028, element: 0x2000, vr: "OB", bytes: Array(iccProfile))
        }

        appendBinary(
            &data,
            group: 0x7FE0,
            element: 0x0010,
            vr: bitsAllocated == 8 ? "OB" : "OW",
            bytes: pixelBytes
        )

        try data.write(to: url)
        return url
    }

    private func appendUS(_ data: inout Data, group: UInt16, element: UInt16, value: UInt16) {
        appendUSValues(&data, group: group, element: element, values: [value])
    }

    private func appendUSValues(_ data: inout Data, group: UInt16, element: UInt16, values: [UInt16]) {
        data.append(contentsOf: withUnsafeBytes(of: group.littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: element.littleEndian) { Array($0) })
        data.append(contentsOf: "US".utf8)
        data.append(UInt8((values.count * 2) & 0xFF))
        data.append(UInt8(((values.count * 2) >> 8) & 0xFF))
        for value in values {
            data.append(contentsOf: withUnsafeBytes(of: value.littleEndian) { Array($0) })
        }
    }

    private func appendCS(_ data: inout Data, group: UInt16, element: UInt16, value: String) {
        var bytes = Array(value.utf8)
        if bytes.count % 2 != 0 {
            bytes.append(0x20)
        }
        data.append(contentsOf: withUnsafeBytes(of: group.littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: element.littleEndian) { Array($0) })
        data.append(contentsOf: "CS".utf8)
        data.append(UInt8(bytes.count & 0xFF))
        data.append(UInt8((bytes.count >> 8) & 0xFF))
        data.append(contentsOf: bytes)
    }

    private func appendOWValues(_ data: inout Data, group: UInt16, element: UInt16, values: [UInt16]) {
        let bytes = values.flatMap { value in
            withUnsafeBytes(of: value.littleEndian) { Array($0) }
        }
        appendBinary(&data, group: group, element: element, vr: "OW", bytes: bytes)
    }

    private func appendBinary(
        _ data: inout Data,
        group: UInt16,
        element: UInt16,
        vr: String,
        bytes: [UInt8]
    ) {
        var padded = bytes
        if padded.count % 2 != 0 {
            padded.append(0)
        }
        data.append(contentsOf: withUnsafeBytes(of: group.littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: element.littleEndian) { Array($0) })
        data.append(contentsOf: vr.utf8)
        data.append(contentsOf: [0x00, 0x00])
        data.append(contentsOf: withUnsafeBytes(of: UInt32(padded.count).littleEndian) { Array($0) })
        data.append(contentsOf: padded)
    }
}
