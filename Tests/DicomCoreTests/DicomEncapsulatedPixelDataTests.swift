import XCTest
@testable import DicomCore

final class DicomEncapsulatedPixelDataTests: XCTestCase {
    func testParserMapsFramesFromBasicOffsetTable() throws {
        let first = Data([0x10, 0x11])
        let second = Data([0x20, 0x21])
        let pixelData = makeEncapsulatedPixelData(
            basicOffsetTable: [0, UInt32(itemLength(for: first))],
            fragments: [first, second]
        )

        let descriptor = try DicomEncapsulatedPixelDataParser().parse(
            data: pixelData,
            pixelDataOffset: 0,
            numberOfFrames: 2
        )

        XCTAssertEqual(descriptor.basicOffsetTable.offsets, [0, UInt32(itemLength(for: first))])
        XCTAssertEqual(descriptor.frameFragmentIndexes, [[0], [1]])
        XCTAssertEqual(descriptor.frame(1, in: pixelData)?.data, second)
    }

    func testParserMapsOneFragmentPerFrameWithoutBasicOffsetTable() throws {
        let first = Data([0x31, 0x32])
        let second = Data([0x41, 0x42])
        let pixelData = makeEncapsulatedPixelData(
            basicOffsetTable: [],
            fragments: [first, second]
        )

        let descriptor = try DicomEncapsulatedPixelDataParser().parse(
            data: pixelData,
            pixelDataOffset: 0,
            numberOfFrames: 2
        )

        XCTAssertEqual(descriptor.frameFragmentIndexes, [[0], [1]])
        XCTAssertEqual(descriptor.frame(0, in: pixelData)?.data, first)
        XCTAssertTrue(diagnosticText(descriptor).contains("Basic Offset Table is empty"))
    }

    func testParserUsesExtendedOffsetTableForMultiFragmentFrame() throws {
        let firstA = Data([0x51, 0x52])
        let firstB = Data([0x53, 0x54])
        let second = Data([0x61, 0x62])
        let secondFrameOffset = UInt64(itemLength(for: firstA) + itemLength(for: firstB))
        let pixelData = makeEncapsulatedPixelData(
            basicOffsetTable: [],
            fragments: [firstA, firstB, second]
        )

        let descriptor = try DicomEncapsulatedPixelDataParser().parse(
            data: pixelData,
            pixelDataOffset: 0,
            numberOfFrames: 2,
            extendedOffsetTableData: uint64Data([0, secondFrameOffset]),
            extendedOffsetTableLengthsData: uint64Data([UInt64(firstA.count + firstB.count), UInt64(second.count)])
        )

        XCTAssertEqual(descriptor.extendedOffsetTable?.offsets, [0, secondFrameOffset])
        XCTAssertEqual(descriptor.frameFragmentIndexes, [[0, 1], [2]])
        XCTAssertEqual(descriptor.frame(0, in: pixelData)?.data, firstA + firstB)
        XCTAssertEqual(descriptor.frame(1, in: pixelData)?.data, second)
    }

    func testParserReportsInconsistentBasicOffsetTable() throws {
        let first = Data([0x71, 0x72])
        let second = Data([0x81, 0x82])
        let pixelData = makeEncapsulatedPixelData(
            basicOffsetTable: [0],
            fragments: [first, second]
        )

        let descriptor = try DicomEncapsulatedPixelDataParser().parse(
            data: pixelData,
            pixelDataOffset: 0,
            numberOfFrames: 2
        )

        XCTAssertEqual(descriptor.frameFragmentIndexes, [[0], [1]])
        XCTAssertTrue(diagnosticText(descriptor).contains("Basic Offset Table has 1 entries"))
    }

    func testDecoderExposesEncapsulatedFrameWithoutCodecDecode() throws {
        let first = Data([0x91, 0x92])
        let second = Data([0xA1, 0xA2])
        let fileURL = try makeTemporaryCompressedDICOM(
            fragments: [first, second],
            basicOffsetTable: [0, UInt32(itemLength(for: first))]
        )
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let decoder = try DCMDecoder(contentsOf: fileURL)
        let descriptor = try XCTUnwrap(decoder.encapsulatedPixelDataDescriptor)
        let frame = try XCTUnwrap(decoder.getEncapsulatedFrame(1))

        XCTAssertTrue(decoder.compressedImage)
        XCTAssertEqual(descriptor.frameFragmentIndexes, [[0], [1]])
        XCTAssertEqual(frame.fragmentIndexes, [1])
        XCTAssertEqual(frame.data, second)
    }

    private func diagnosticText(_ descriptor: DicomEncapsulatedPixelDataDescriptor) -> String {
        descriptor.diagnostics.map(\.message).joined(separator: "\n")
    }

    private func makeTemporaryCompressedDICOM(
        fragments: [Data],
        basicOffsetTable: [UInt32]
    ) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("encapsulated_pixel_data_\(UUID().uuidString).dcm")
        var data = Data(count: 128)
        data.append(contentsOf: "DICM".utf8)

        appendElement(tag: DicomTag.transferSyntaxUID.rawValue, vr: "UI", value: ui(DicomTransferSyntax.jpegBaseline.rawValue), to: &data)
        appendElement(tag: DicomTag.samplesPerPixel.rawValue, vr: "US", value: uint16Data(1), to: &data)
        appendElement(tag: DicomTag.photometricInterpretation.rawValue, vr: "CS", value: stringData("MONOCHROME2", padding: 0x20), to: &data)
        appendElement(tag: DicomTag.numberOfFrames.rawValue, vr: "IS", value: stringData("\(fragments.count)", padding: 0x20), to: &data)
        appendElement(tag: DicomTag.rows.rawValue, vr: "US", value: uint16Data(1), to: &data)
        appendElement(tag: DicomTag.columns.rawValue, vr: "US", value: uint16Data(1), to: &data)
        appendElement(tag: DicomTag.bitsAllocated.rawValue, vr: "US", value: uint16Data(8), to: &data)
        appendElement(tag: DicomTag.bitsStored.rawValue, vr: "US", value: uint16Data(8), to: &data)
        appendElement(tag: DicomTag.highBit.rawValue, vr: "US", value: uint16Data(7), to: &data)
        appendElement(tag: DicomTag.pixelRepresentation.rawValue, vr: "US", value: uint16Data(0), to: &data)
        appendPixelData(
            makeEncapsulatedPixelData(basicOffsetTable: basicOffsetTable, fragments: fragments),
            to: &data
        )

        try data.write(to: url)
        return url
    }

    private func makeEncapsulatedPixelData(basicOffsetTable: [UInt32], fragments: [Data]) -> Data {
        var data = Data()
        appendItem(uint32Data(basicOffsetTable), to: &data)
        for fragment in fragments {
            appendItem(fragment, to: &data)
        }
        appendTag(0xFFFEE0DD, to: &data)
        appendUInt32(0, to: &data)
        return data
    }

    private func appendPixelData(_ value: Data, to data: inout Data) {
        appendTag(DicomTag.pixelData.rawValue, to: &data)
        data.append(contentsOf: "OB".utf8)
        data.append(contentsOf: [0x00, 0x00])
        appendUInt32(0xFFFFFFFF, to: &data)
        data.append(value)
    }

    private func appendElement(tag: Int, vr: String, value: Data, to data: inout Data) {
        appendTag(tag, to: &data)
        data.append(contentsOf: vr.utf8)
        if ["OB", "OW", "OV", "SQ", "UN", "UT"].contains(vr) {
            data.append(contentsOf: [0x00, 0x00])
            appendUInt32(UInt32(value.count), to: &data)
        } else {
            appendUInt16(UInt16(value.count), to: &data)
        }
        data.append(value)
    }

    private func appendItem(_ value: Data, to data: inout Data) {
        appendTag(0xFFFEE000, to: &data)
        appendUInt32(UInt32(value.count), to: &data)
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

    private func uint16Data(_ value: UInt16) -> Data {
        var data = Data()
        appendUInt16(value, to: &data)
        return data
    }

    private func uint32Data(_ values: [UInt32]) -> Data {
        values.reduce(into: Data()) { data, value in
            appendUInt32(value, to: &data)
        }
    }

    private func uint64Data(_ values: [UInt64]) -> Data {
        values.reduce(into: Data()) { data, value in
            data.append(UInt8(value & 0xFF))
            data.append(UInt8((value >> 8) & 0xFF))
            data.append(UInt8((value >> 16) & 0xFF))
            data.append(UInt8((value >> 24) & 0xFF))
            data.append(UInt8((value >> 32) & 0xFF))
            data.append(UInt8((value >> 40) & 0xFF))
            data.append(UInt8((value >> 48) & 0xFF))
            data.append(UInt8((value >> 56) & 0xFF))
        }
    }

    private func ui(_ value: String) -> Data {
        stringData(value, padding: 0x00)
    }

    private func stringData(_ value: String, padding: UInt8) -> Data {
        var data = Data(value.utf8)
        if data.count % 2 != 0 {
            data.append(padding)
        }
        return data
    }

    private func itemLength(for value: Data) -> Int {
        8 + value.count
    }
}
