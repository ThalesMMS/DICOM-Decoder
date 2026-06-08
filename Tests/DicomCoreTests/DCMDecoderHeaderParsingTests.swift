import XCTest
@testable import DicomCore

final class DCMDecoderHeaderParsingTests: XCTestCase {
    func testUndefinedLengthSequenceBeforeDimensionsDoesNotSuppressDimensionHandlers() throws {
        let url = try makeDicomWithUndefinedSequenceBeforeDimensions(rows: 3, columns: 5)
        let decoder = try DCMDecoder(contentsOf: url)

        XCTAssertEqual(decoder.height, 3)
        XCTAssertEqual(decoder.width, 5)
        XCTAssertEqual(decoder.intValue(for: .rows), 3)
        XCTAssertEqual(decoder.intValue(for: .columns), 5)
    }

    private func makeDicomWithUndefinedSequenceBeforeDimensions(rows: UInt16, columns: UInt16) throws -> URL {
        var data = Data(repeating: 0, count: 128)
        data.append(contentsOf: "DICM".utf8)

        appendElement(DicomTag.transferSyntaxUID.rawValue, vr: "UI", value: paddedUID("1.2.840.10008.1.2.1"), to: &data)
        appendUndefinedDerivationCodeSequence(to: &data)
        appendElement(DicomTag.samplesPerPixel.rawValue, vr: "US", value: uint16(rows == 0 ? 0 : 1), to: &data)
        appendElement(DicomTag.photometricInterpretation.rawValue, vr: "CS", value: paddedASCII("MONOCHROME2"), to: &data)
        appendElement(DicomTag.rows.rawValue, vr: "US", value: uint16(rows), to: &data)
        appendElement(DicomTag.columns.rawValue, vr: "US", value: uint16(columns), to: &data)
        appendElement(DicomTag.bitsAllocated.rawValue, vr: "US", value: uint16(16), to: &data)
        appendElement(DicomTag.pixelRepresentation.rawValue, vr: "US", value: uint16(0), to: &data)

        let pixelCount = Int(rows) * Int(columns)
        appendElement(DicomTag.pixelData.rawValue, vr: "OW", value: Data(repeating: 0, count: pixelCount * 2), to: &data)

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("dcm")
        try data.write(to: url)
        return url
    }

    private func appendUndefinedDerivationCodeSequence(to data: inout Data) {
        appendTag(0x00089215, to: &data)
        data.append(contentsOf: "SQ".utf8)
        data.append(contentsOf: [0, 0])
        appendUInt32(UInt32.max, to: &data)

        appendTag(0xFFFEE000, to: &data)
        appendUInt32(UInt32.max, to: &data)
        appendElement(0x00080100, vr: "SH", value: paddedASCII("121327"), to: &data)
        appendElement(0x00080102, vr: "SH", value: paddedASCII("DCM"), to: &data)
        appendElement(0x00080104, vr: "LO", value: paddedASCII("Full fidelity image"), to: &data)
        appendTag(0xFFFEE00D, to: &data)
        appendUInt32(0, to: &data)

        appendTag(0xFFFEE0DD, to: &data)
        appendUInt32(0, to: &data)
    }

    private func appendElement(_ tag: Int, vr: String, value: Data, to data: inout Data) {
        appendTag(tag, to: &data)
        data.append(contentsOf: vr.utf8)
        if ["OB", "OD", "OF", "OW", "OV", "SQ", "UN", "UR", "UT"].contains(vr) {
            data.append(contentsOf: [0, 0])
            appendUInt32(UInt32(value.count), to: &data)
        } else {
            appendUInt16(UInt16(value.count), to: &data)
        }
        data.append(value)
    }

    private func appendTag(_ tag: Int, to data: inout Data) {
        appendUInt16(UInt16((tag >> 16) & 0xFFFF), to: &data)
        appendUInt16(UInt16(tag & 0xFFFF), to: &data)
    }

    private func appendUInt16(_ value: UInt16, to data: inout Data) {
        data.append(UInt8(value & 0xFF))
        data.append(UInt8((value >> 8) & 0xFF))
    }

    private func appendUInt32(_ value: UInt32, to data: inout Data) {
        data.append(UInt8(value & 0xFF))
        data.append(UInt8((value >> 8) & 0xFF))
        data.append(UInt8((value >> 16) & 0xFF))
        data.append(UInt8((value >> 24) & 0xFF))
    }

    private func uint16(_ value: UInt16) -> Data {
        Data([UInt8(value & 0xFF), UInt8((value >> 8) & 0xFF)])
    }

    private func paddedASCII(_ value: String) -> Data {
        var data = Data(value.utf8)
        if data.count % 2 != 0 {
            data.append(0x20)
        }
        return data
    }

    private func paddedUID(_ value: String) -> Data {
        var data = Data(value.utf8)
        if data.count % 2 != 0 {
            data.append(0)
        }
        return data
    }
}
