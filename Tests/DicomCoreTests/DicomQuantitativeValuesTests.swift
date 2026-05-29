import XCTest
@testable import DicomCore

final class DicomQuantitativeValuesTests: XCTestCase {
    func testRealWorldValueLinearMappingReturnsPhysicalUnits() throws {
        let url = try makeTemporaryDICOM(
            pixelValues: [4, 10],
            extraElements: [
                sequence(.realWorldValueMappingSequence, [
                    DicomDataSet(elements: [
                        us(.realWorldValueFirstValueMapped, 0),
                        us(.realWorldValueLastValueMapped, 100),
                        string(.realWorldValueLUTLabel, vr: .SH, "LINEAR"),
                        fd(.realWorldValueIntercept, [2.0]),
                        fd(.realWorldValueSlope, [0.5]),
                        unitSequence(codeValue: "mg/ml", codingScheme: "UCUM", meaning: "milligram per milliliter")
                    ])
                ])
            ]
        )
        defer { try? FileManager.default.removeItem(at: url) }

        let decoder = try DCMDecoder(contentsOf: url)
        let profile = decoder.quantitativeValueProfile
        let value = try XCTUnwrap(decoder.quantitativeValue(at: 1))

        XCTAssertEqual(profile.realWorldValueMaps.count, 1)
        XCTAssertEqual(profile.realWorldValue(forStoredPixelValue: 10), 7.0)
        XCTAssertEqual(value.storedValue, 10)
        XCTAssertEqual(value.modalityValue, 10.0)
        XCTAssertEqual(value.physicalValue, 7.0)
        XCTAssertEqual(value.physicalUnit?.codeValue, "mg/ml")
        XCTAssertEqual(value.physicalRange, 2.0...52.0)
        XCTAssertEqual(value.source, .realWorldValueMap(label: "LINEAR"))
    }

    func testRealWorldValueLUTMappingReturnsLookupEntry() throws {
        let url = try makeTemporaryDICOM(
            pixelValues: [2],
            extraElements: [
                sequence(.realWorldValueMappingSequence, [
                    DicomDataSet(elements: [
                        us(.realWorldValueFirstValueMapped, 1),
                        us(.realWorldValueLastValueMapped, 3),
                        string(.realWorldValueLUTLabel, vr: .SH, "LUT"),
                        fd(.realWorldValueLUTData, [10.0, 20.0, 30.0]),
                        unitSequence(codeValue: "1", codingScheme: "UCUM", meaning: "ratio")
                    ])
                ])
            ]
        )
        defer { try? FileManager.default.removeItem(at: url) }

        let decoder = try DCMDecoder(contentsOf: url)
        let value = try XCTUnwrap(decoder.quantitativeValue(
            at: 0,
            preferredRealWorldValueMapLabel: "LUT"
        ))

        XCTAssertEqual(value.storedValue, 2)
        XCTAssertEqual(value.physicalValue, 20.0)
        XCTAssertEqual(value.physicalUnit?.codeMeaning, "ratio")
        XCTAssertEqual(value.physicalRange, 10.0...30.0)
    }

    func testSUVBodyWeightUsesPETMetadataWhenPresent() throws {
        let url = try makeTemporaryDICOM(
            pixelValues: [1000],
            modality: "PT",
            extraElements: [
                string(.units, vr: .CS, "BQML"),
                string(.rescaleType, vr: .LO, "BQML"),
                ds(.patientWeight, ["70"]),
                ds(.decayFactor, ["1"]),
                sequence(.radiopharmaceuticalInformationSequence, [
                    DicomDataSet(elements: [
                        ds(.radionuclideTotalDose, ["350000000"])
                    ])
                ])
            ]
        )
        defer { try? FileManager.default.removeItem(at: url) }

        let decoder = try DCMDecoder(contentsOf: url)
        let value = try XCTUnwrap(decoder.quantitativeValue(at: 0, suvType: .bw))

        XCTAssertEqual(value.storedValue, 1000)
        XCTAssertEqual(value.modalityValue, 1000.0)
        XCTAssertEqual(value.modalityUnit, "BQML")
        XCTAssertEqual(value.physicalValue ?? .nan, 0.2, accuracy: 0.000001)
        XCTAssertEqual(value.physicalUnit?.codeMeaning, "Standardized Uptake Value body weight")
        XCTAssertEqual(value.source, .suv(.bw))
        XCTAssertEqual(decoder.quantitativeValueProfile.suvMetadata?.diagnostics(for: .bw), [])
    }

    func testSUVVariantsUsePatientSizeCorrectionFactors() throws {
        let url = try makeTemporaryDICOM(
            pixelValues: [1000],
            modality: "PT",
            extraElements: [
                string(.units, vr: .CS, "BQML"),
                ds(.patientWeight, ["70"]),
                ds(.patientSize, ["1.75"]),
                string(.patientSex, vr: .CS, "M"),
                ds(.decayFactor, ["1"]),
                sequence(.radiopharmaceuticalInformationSequence, [
                    DicomDataSet(elements: [
                        ds(.radionuclideTotalDose, ["350000000"])
                    ])
                ])
            ]
        )
        defer { try? FileManager.default.removeItem(at: url) }

        let decoder = try DCMDecoder(contentsOf: url)
        let metadata = try XCTUnwrap(decoder.quantitativeValueProfile.suvMetadata)

        XCTAssertEqual(metadata.patientSizeCorrectionFactor(for: .lbm) ?? .nan, 57_800, accuracy: 0.001)
        XCTAssertEqual(metadata.patientSizeCorrectionFactor(for: .ibw) ?? .nan, 72_380, accuracy: 0.001)
        XCTAssertEqual(metadata.suvValue(forActivityConcentrationBqPerMl: 1000, type: .lbm) ?? .nan, 0.165142857, accuracy: 0.000001)
        XCTAssertEqual(metadata.suvValue(forActivityConcentrationBqPerMl: 1000, type: .ibw) ?? .nan, 0.2068, accuracy: 0.000001)
        XCTAssertNotNil(metadata.suvValue(forActivityConcentrationBqPerMl: 1000, type: .bsa))
        XCTAssertEqual(metadata.diagnostics(for: .lbm), [])
        XCTAssertEqual(metadata.diagnostics(for: .bsa), [])
        XCTAssertEqual(metadata.diagnostics(for: .ibw), [])
    }

    func testSUVBodyWeightAcceptsAlreadyNormalizedGMLUnits() throws {
        let url = try makeTemporaryDICOM(
            pixelValues: [5],
            modality: "PT",
            extraElements: [
                string(.units, vr: .CS, "GML")
            ]
        )
        defer { try? FileManager.default.removeItem(at: url) }

        let decoder = try DCMDecoder(contentsOf: url)
        let value = try XCTUnwrap(decoder.quantitativeValue(at: 0, suvType: .bw))
        let metadata = try XCTUnwrap(decoder.quantitativeValueProfile.suvMetadata)

        XCTAssertEqual(value.physicalValue, 5.0)
        XCTAssertEqual(metadata.diagnostics(for: .bw), [])
    }

    func testSUVReportsMissingRequiredPETMetadata() throws {
        let url = try makeTemporaryDICOM(
            pixelValues: [1000],
            modality: "PT",
            extraElements: [
                string(.units, vr: .CS, "BQML")
            ]
        )
        defer { try? FileManager.default.removeItem(at: url) }

        let decoder = try DCMDecoder(contentsOf: url)
        let profile = decoder.quantitativeValueProfile
        let value = try XCTUnwrap(decoder.quantitativeValue(at: 0, suvType: .bw))
        let missingTags = Set(profile.suvMetadata?.diagnostics(for: .bw).compactMap(\.tag) ?? [])

        XCTAssertNil(value.physicalValue)
        XCTAssertTrue(missingTags.contains(DicomTag.patientWeight.rawValue))
        XCTAssertTrue(missingTags.contains(DicomTag.radionuclideTotalDose.rawValue))
        XCTAssertTrue(missingTags.contains(DicomTag.radionuclideHalfLife.rawValue))
        XCTAssertTrue(missingTags.contains(DicomTag.radiopharmaceuticalStartTime.rawValue))
        XCTAssertTrue(missingTags.contains(DicomTag.acquisitionTime.rawValue))
    }

    private func makeTemporaryDICOM(
        pixelValues: [UInt16],
        modality: String = "OT",
        extraElements: [DicomDataElement] = []
    ) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("quantitative_values_\(UUID().uuidString).dcm")
        let dataSet = DicomDataSet(elements: [
            string(0x00080016, vr: .UI, DicomDataSetWriter.defaultSecondaryCaptureImageStorageSOPClassUID),
            string(.sopInstanceUID, vr: .UI, "1.2.826.0.1.3680043.10.224.\(Int.random(in: 1...999999))"),
            string(.modality, vr: .CS, modality),
            us(.samplesPerPixel, 1),
            string(.photometricInterpretation, vr: .CS, "MONOCHROME2"),
            us(.rows, 1),
            us(.columns, pixelValues.count),
            us(.bitsAllocated, 16),
            us(.bitsStored, 16),
            us(.highBit, 15),
            us(.pixelRepresentation, 0),
            bytes(.pixelData, vr: .OW, Data(littleEndianBytes(values: pixelValues)))
        ] + extraElements)

        let data = try DicomDataSetWriter.part10Data(from: dataSet)
        try data.write(to: url)
        return url
    }

    private func unitSequence(codeValue: String, codingScheme: String, meaning: String) -> DicomDataElement {
        sequence(.measurementUnitsCodeSequence, [
            DicomDataSet(elements: [
                string(.codeValue, vr: .SH, codeValue),
                string(.codingSchemeDesignator, vr: .SH, codingScheme),
                string(.codeMeaning, vr: .LO, meaning)
            ])
        ])
    }

    private func sequence(_ tag: DicomTag, _ dataSets: [DicomDataSet]) -> DicomDataElement {
        DicomDataElement(
            tag: tag.rawValue,
            vr: .SQ,
            value: .sequence(dataSets.map { DicomSequenceItem(dataSet: $0) })
        )
    }

    private func string(_ tag: DicomTag, vr: DicomVR, _ value: String) -> DicomDataElement {
        string(tag.rawValue, vr: vr, value)
    }

    private func string(_ tag: Int, vr: DicomVR, _ value: String) -> DicomDataElement {
        DicomDataElement(tag: tag, vr: vr, value: .strings([value]))
    }

    private func ds(_ tag: DicomTag, _ values: [String]) -> DicomDataElement {
        DicomDataElement(tag: tag.rawValue, vr: .DS, value: .strings(values))
    }

    private func us(_ tag: DicomTag, _ value: Int) -> DicomDataElement {
        us(tag, [value])
    }

    private func us(_ tag: DicomTag, _ values: [Int]) -> DicomDataElement {
        DicomDataElement(tag: tag.rawValue, vr: .US, value: .unsignedIntegers(values.map(UInt.init)))
    }

    private func fd(_ tag: DicomTag, _ values: [Double]) -> DicomDataElement {
        DicomDataElement(tag: tag.rawValue, vr: .FD, value: .floats(values))
    }

    private func bytes(_ tag: DicomTag, vr: DicomVR, _ value: Data) -> DicomDataElement {
        DicomDataElement(tag: tag.rawValue, vr: vr, value: .bytes(value))
    }

    private func littleEndianBytes(values: [UInt16]) -> [UInt8] {
        values.flatMap { value in
            withUnsafeBytes(of: value.littleEndian) { Array($0) }
        }
    }
}
