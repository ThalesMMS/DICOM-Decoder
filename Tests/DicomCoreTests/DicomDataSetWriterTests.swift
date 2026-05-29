import XCTest
@testable import DicomCore

final class DicomDataSetWriterTests: XCTestCase {
    private let sopClassUIDTag = 0x00080016
    private let procedureCodeSequenceTag = 0x00081032
    private let codeValueTag = 0x00080100
    private let codeMeaningTag = 0x00080104
    private let privateTag = 0x00111010

    func testWriterAppliesDatasetEditsAndReopensPart10File() throws {
        var dataSet = makeBaseDataSet(pixelBytes: Data([0x2A, 0x00]))
        dataSet.set(DicomDataElement(tag: DicomTag.patientName.rawValue,
                                     vr: .PN,
                                     value: .strings(["Roe^Richard"])))
        dataSet.set(DicomDataElement(tag: privateTag, vr: .LO, value: .strings(["remove-me"])))
        dataSet.remove(privateTag)

        let url = temporaryDICOMURL()
        defer { try? FileManager.default.removeItem(at: url) }

        try DicomDataSetWriter.write(dataSet, to: url)

        let decoder = try DCMDecoder(contentsOf: url)
        let decodedDataSet = decoder.dataSet

        XCTAssertTrue(DicomTransferSyntax.explicitVRLittleEndian.matches(decoder.info(for: .transferSyntaxUID)))
        XCTAssertEqual(decodedDataSet.personName(for: .patientName)?.familyName, "Roe")
        XCTAssertEqual(decodedDataSet.personName(for: .patientName)?.givenName, "Richard")
        XCTAssertEqual(decodedDataSet.string(for: .modality), "CT")
        XCTAssertEqual(decodedDataSet.int(for: .rows), 1)
        XCTAssertEqual(decodedDataSet.int(for: .columns), 1)
        XCTAssertEqual(decodedDataSet.decimalStrings(for: .pixelSpacing), [0.5, 0.75])
        XCTAssertNil(decodedDataSet.element(for: privateTag))
        XCTAssertEqual(try XCTUnwrap(decoder.getPixels16()), [42])
    }

    func testWriterRoundTripsImplicitVRLittleEndian() throws {
        let dataSet = makeBaseDataSet(pixelBytes: Data([0x2B, 0x00]))
        let url = temporaryDICOMURL()
        defer { try? FileManager.default.removeItem(at: url) }

        try DicomDataSetWriter.write(
            dataSet,
            to: url,
            options: DicomPart10WriterOptions(transferSyntax: .implicitVRLittleEndian)
        )

        let decoder = try DCMDecoder(contentsOf: url)

        XCTAssertTrue(DicomTransferSyntax.implicitVRLittleEndian.matches(decoder.info(for: .transferSyntaxUID)))
        XCTAssertEqual(decoder.dataSet.personName(for: .patientName)?.familyName, "Doe")
        XCTAssertEqual(decoder.dataSet.string(for: .modality), "CT")
        XCTAssertEqual(decoder.width, 1)
        XCTAssertEqual(decoder.height, 1)
        XCTAssertEqual(try XCTUnwrap(decoder.getPixels16()), [43])
    }

    func testWriterRoundTripsLegacyExplicitVRBigEndian() throws {
        let dataSet = makeBaseDataSet(pixelBytes: Data([0x00, 0x2C]))
        let url = temporaryDICOMURL()
        defer { try? FileManager.default.removeItem(at: url) }

        try DicomDataSetWriter.write(
            dataSet,
            to: url,
            options: DicomPart10WriterOptions(transferSyntax: .explicitVRBigEndian)
        )

        let decoder = try DCMDecoder(contentsOf: url)

        XCTAssertTrue(DicomTransferSyntax.explicitVRBigEndian.matches(decoder.info(for: .transferSyntaxUID)))
        XCTAssertFalse(decoder.currentLittleEndian())
        XCTAssertEqual(decoder.dataSet.string(for: .modality), "CT")
        XCTAssertEqual(decoder.width, 1)
        XCTAssertEqual(decoder.height, 1)
        XCTAssertEqual(try XCTUnwrap(decoder.getPixels16()), [44])
    }

    func testWriterEncodesDefinedLengthSequences() throws {
        let item = DicomSequenceItem(dataSet: DicomDataSet(elements: [
            DicomDataElement(tag: codeValueTag, vr: .SH, value: .strings(["CHEST"])),
            DicomDataElement(tag: codeMeaningTag, vr: .LO, value: .strings(["Chest study"]))
        ]))
        let dataSet = makeBaseDataSet(pixelBytes: Data([0x2D, 0x00])).setting(
            DicomDataElement(tag: procedureCodeSequenceTag,
                             vr: .SQ,
                             value: .sequence([item]))
        )

        let data = try DicomDataSetWriter.part10Data(from: dataSet)
        let sequenceHeader = Data([0x08, 0x00, 0x32, 0x10, 0x53, 0x51, 0x00, 0x00])
        let sequenceRange = try XCTUnwrap(data.range(of: sequenceHeader))
        let sequenceLength = Int(readUInt32LittleEndian(data, at: sequenceRange.upperBound))
        let itemOffset = sequenceRange.upperBound + 4

        XCTAssertGreaterThan(sequenceLength, 0)
        XCTAssertEqual(Array(data[itemOffset..<(itemOffset + 4)]), [0xFE, 0xFF, 0x00, 0xE0])
        XCTAssertEqual(Int(readUInt32LittleEndian(data, at: itemOffset + 4)) + 8, sequenceLength)
        XCTAssertNotNil(data.range(of: Data([0x08, 0x00, 0x00, 0x01, 0x53, 0x48])))
        XCTAssertNotNil(data.range(of: Data([0x08, 0x00, 0x04, 0x01, 0x4C, 0x4F])))

        let url = temporaryDICOMURL()
        defer { try? FileManager.default.removeItem(at: url) }
        try data.write(to: url)

        let decoder = try DCMDecoder(contentsOf: url)
        XCTAssertEqual(decoder.dataSet.element(for: procedureCodeSequenceTag)?.vr, .SQ)
    }

    func testWriterRejectsCompressedTransferSyntax() throws {
        XCTAssertThrowsError(
            try DicomDataSetWriter.part10Data(
                from: makeBaseDataSet(pixelBytes: Data([0x2E, 0x00])),
                options: DicomPart10WriterOptions(transferSyntax: .jpegBaseline)
            )
        ) { error in
            XCTAssertEqual(error as? DicomDataSetWriterError, .compressedTransferSyntaxUnsupported(DicomTransferSyntax.jpegBaseline.rawValue))
        }
    }

    func testWriterSupportsDeflatedExplicitVRLittleEndian() throws {
        let data = try DicomDataSetWriter.part10Data(
            from: makeBaseDataSet(pixelBytes: Data([0x2F, 0x00])),
            options: DicomPart10WriterOptions(transferSyntax: .deflatedExplicitVRLittleEndian)
        )

        XCTAssertNotNil(data.range(of: Data(DicomTransferSyntax.deflatedExplicitVRLittleEndian.rawValue.utf8)))

        let url = temporaryDICOMURL()
        defer { try? FileManager.default.removeItem(at: url) }
        try data.write(to: url)

        let decoder = try DCMDecoder(contentsOf: url)
        XCTAssertTrue(DicomTransferSyntax.deflatedExplicitVRLittleEndian.matches(decoder.info(for: .transferSyntaxUID)))
        XCTAssertFalse(decoder.compressedImage)
        XCTAssertEqual(try XCTUnwrap(decoder.getPixels16()), [47])
    }

    func testGeneratedUIDUsesDicomUIDSyntaxEnvelope() {
        let uid = DicomDataSetWriter.makeUID()

        XCTAssertTrue(uid.hasPrefix("2.25."))
        XCTAssertLessThanOrEqual(uid.count, 64)
        XCTAssertTrue(uid.allSatisfy { $0.isNumber || $0 == "." })
        XCTAssertNotNil(DicomUID(uid))
    }

    private func makeBaseDataSet(pixelBytes: Data) -> DicomDataSet {
        DicomDataSet(elements: [
            DicomDataElement(tag: sopClassUIDTag,
                             vr: .UI,
                             value: .strings([DicomDataSetWriter.defaultSecondaryCaptureImageStorageSOPClassUID])),
            DicomDataElement(tag: DicomTag.sopInstanceUID.rawValue,
                             vr: .UI,
                             value: .strings(["2.25.123456789"])),
            DicomDataElement(tag: DicomTag.studyInstanceUID.rawValue,
                             vr: .UI,
                             value: .strings(["2.25.123456790"])),
            DicomDataElement(tag: DicomTag.seriesInstanceUID.rawValue,
                             vr: .UI,
                             value: .strings(["2.25.123456791"])),
            DicomDataElement(tag: DicomTag.patientName.rawValue,
                             vr: .PN,
                             value: .strings(["Doe^Jane"])),
            DicomDataElement(tag: DicomTag.patientID.rawValue,
                             vr: .LO,
                             value: .strings(["P-1"])),
            DicomDataElement(tag: DicomTag.modality.rawValue,
                             vr: .CS,
                             value: .strings(["CT"])),
            DicomDataElement(tag: DicomTag.pixelSpacing.rawValue,
                             vr: .DS,
                             value: .strings(["0.5", "0.75"])),
            DicomDataElement(tag: DicomTag.samplesPerPixel.rawValue,
                             vr: .US,
                             value: .unsignedIntegers([1])),
            DicomDataElement(tag: DicomTag.photometricInterpretation.rawValue,
                             vr: .CS,
                             value: .strings(["MONOCHROME2"])),
            DicomDataElement(tag: DicomTag.rows.rawValue,
                             vr: .US,
                             value: .unsignedIntegers([1])),
            DicomDataElement(tag: DicomTag.columns.rawValue,
                             vr: .US,
                             value: .unsignedIntegers([1])),
            DicomDataElement(tag: DicomTag.bitsAllocated.rawValue,
                             vr: .US,
                             value: .unsignedIntegers([16])),
            DicomDataElement(tag: DicomTag.bitsStored.rawValue,
                             vr: .US,
                             value: .unsignedIntegers([16])),
            DicomDataElement(tag: DicomTag.highBit.rawValue,
                             vr: .US,
                             value: .unsignedIntegers([15])),
            DicomDataElement(tag: DicomTag.pixelRepresentation.rawValue,
                             vr: .US,
                             value: .unsignedIntegers([0])),
            DicomDataElement(tag: DicomTag.pixelData.rawValue,
                             vr: .OW,
                             value: .bytes(pixelBytes))
        ])
    }

    private func temporaryDICOMURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("dcm")
    }

    private func readUInt32LittleEndian(_ data: Data, at offset: Int) -> UInt32 {
        UInt32(data[offset]) |
            UInt32(data[offset + 1]) << 8 |
            UInt32(data[offset + 2]) << 16 |
            UInt32(data[offset + 3]) << 24
    }
}
