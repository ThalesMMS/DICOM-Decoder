import simd
import XCTest
@testable import DicomCore

final class DicomParametricMapTests: XCTestCase {
    func testParametricMapParsesIntegerScalarVolumeWithUnitsQuantityGeometryAndSources() throws {
        let sourceReference = DicomSourceImageReference(
            referencedSOPClassUID: "1.2.840.10008.5.1.4.1.1.4",
            referencedSOPInstanceUID: "2.25.6001",
            referencedFrameNumbers: [1]
        )
        let storedValues: [UInt16] = [100, 200, 300, 400, 500, 600, 700, 800]
        let units = DicomCodedConcept(codeValue: "mm2/s", codingSchemeDesignator: "UCUM", codeMeaning: "square millimeter per second")
        let quantityName = DicomCodedConcept(codeValue: "246205007", codingSchemeDesignator: "SCT", codeMeaning: "Quantity")
        let quantityCode = DicomCodedConcept(codeValue: "113041", codingSchemeDesignator: "DCM", codeMeaning: "Apparent Diffusion Coefficient")

        let dataSet = DicomDataSet(elements: [
            string(.sopClassUID, vr: .UI, DicomParametricMap.storageSOPClassUID),
            string(.sopInstanceUID, vr: .UI, "2.25.6101"),
            string(.modality, vr: .CS, "PM"),
            us(.samplesPerPixel, 1),
            string(.photometricInterpretation, vr: .CS, "MONOCHROME2"),
            string(.numberOfFrames, vr: .IS, "2"),
            us(.rows, 2),
            us(.columns, 2),
            us(.bitsAllocated, 16),
            us(.bitsStored, 16),
            us(.highBit, 15),
            us(.pixelRepresentation, 0),
            sequence(.sharedFunctionalGroupsSequence, [
                DicomDataSet(elements: [
                    sequence(.pixelMeasuresSequence, [
                        DicomDataSet(elements: [
                            ds(.pixelSpacing, ["0.7", "0.8"]),
                            ds(.sliceThickness, ["2.5"]),
                            ds(.sliceSpacing, ["2.5"])
                        ])
                    ]),
                    sequence(.planeOrientationSequence, [
                        DicomDataSet(elements: [
                            ds(.imageOrientationPatient, ["1", "0", "0", "0", "1", "0"])
                        ])
                    ]),
                    sequence(.realWorldValueMappingSequence, [
                        realWorldValueMap(
                            label: "ADC",
                            first: 0,
                            last: 1000,
                            intercept: 0,
                            slope: 0.001,
                            units: units,
                            quantityName: quantityName,
                            quantityCode: quantityCode
                        )
                    ])
                ])
            ]),
            sequence(.perFrameFunctionalGroupsSequence, [
                frameFunctionalGroup(index: 0, z: 0, sourceReference: sourceReference),
                frameFunctionalGroup(index: 1, z: 2.5, sourceReference: sourceReference)
            ]),
            bytes(.pixelData, vr: .OW, uint16Data(storedValues))
        ])

        let decoder = try open(dataSet: dataSet)
        let map = try XCTUnwrap(decoder.parametricMap)

        XCTAssertEqual(map.sopInstanceUID, "2.25.6101")
        XCTAssertEqual(map.rows, 2)
        XCTAssertEqual(map.columns, 2)
        XCTAssertEqual(map.frameCount, 2)
        XCTAssertEqual(map.scalarVolume.scalarValues, storedValues.map(Double.init))
        assertEqual(map.scalarVolume.physicalValues ?? [], [0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8], accuracy: 1e-12)
        XCTAssertEqual(map.scalarVolume.units, units)
        XCTAssertEqual(map.scalarVolume.quantityDefinitions.first?.conceptName, quantityName)
        XCTAssertEqual(map.scalarVolume.quantityDefinitions.first?.conceptCode, quantityCode)

        XCTAssertEqual(map.frames[0].sourceImageReferences, [sourceReference])
        XCTAssertEqual(map.frames[1].geometry?.imagePositionPatient, SIMD3<Double>(0, 0, 2.5))
        XCTAssertEqual(map.frames[0].geometry?.imageOrientationPatient?.normal, SIMD3<Double>(0, 0, 1))
        XCTAssertEqual(map.frames[0].geometry?.pixelMeasures?.pixelSpacing, SIMD2<Double>(0.7, 0.8))
        XCTAssertEqual(map.frames[0].realWorldValueMap?.label, "ADC")
        assertEqual(map.frames[1].physicalValues ?? [], [0.5, 0.6, 0.7, 0.8], accuracy: 1e-12)
    }

    func testParametricMapParsesFloatPixelDataAndDoubleFloatRealWorldValueRange() throws {
        let units = DicomCodedConcept(codeValue: "{ratio}", codingSchemeDesignator: "UCUM", codeMeaning: "ratio")
        let quantityName = DicomCodedConcept(codeValue: "246205007", codingSchemeDesignator: "SCT", codeMeaning: "Quantity")
        let quantityCode = DicomCodedConcept(codeValue: "126397", codingSchemeDesignator: "DCM", codeMeaning: "Relative Regional Blood Flow")
        let scalarValues = [1.5, 2.5, 3.5, 4.5]

        let dataSet = DicomDataSet(elements: [
            string(.sopClassUID, vr: .UI, DicomParametricMap.storageSOPClassUID),
            string(.sopInstanceUID, vr: .UI, "2.25.6201"),
            string(.modality, vr: .CS, "PM"),
            us(.samplesPerPixel, 1),
            string(.photometricInterpretation, vr: .CS, "MONOCHROME2"),
            string(.numberOfFrames, vr: .IS, "1"),
            us(.rows, 2),
            us(.columns, 2),
            us(.bitsAllocated, 32),
            sequence(.realWorldValueMappingSequence, [
                realWorldValueMap(
                    label: "rCBF",
                    doubleFirst: 0,
                    doubleLast: 10,
                    intercept: 1,
                    slope: 2,
                    units: units,
                    quantityName: quantityName,
                    quantityCode: quantityCode
                )
            ]),
            DicomDataElement(tag: DicomTag.floatPixelData.rawValue, vr: .OF, value: .floats(scalarValues))
        ])

        let decoder = try open(dataSet: dataSet)
        let map = try XCTUnwrap(decoder.parametricMap)

        assertEqual(map.scalarVolume.scalarValues, scalarValues, accuracy: 1e-6)
        assertEqual(map.scalarVolume.physicalValues ?? [], [4, 6, 8, 10], accuracy: 1e-6)
        XCTAssertEqual(map.frames[0].units, units)
        XCTAssertEqual(map.frames[0].quantityDefinitions.first?.conceptCode, quantityCode)
    }

    private func open(dataSet: DicomDataSet) throws -> DCMDecoder {
        let data = try DicomDataSetWriter.part10Data(
            from: dataSet,
            options: DicomPart10WriterOptions(mediaStorageSOPClassUID: DicomParametricMap.storageSOPClassUID)
        )
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("parametric_map_\(UUID().uuidString).dcm")
        try data.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        return try DCMDecoder(contentsOf: url)
    }

    private func realWorldValueMap(
        label: String,
        first: Int? = nil,
        last: Int? = nil,
        doubleFirst: Double? = nil,
        doubleLast: Double? = nil,
        intercept: Double,
        slope: Double,
        units: DicomCodedConcept,
        quantityName: DicomCodedConcept,
        quantityCode: DicomCodedConcept
    ) -> DicomDataSet {
        var elements: [DicomDataElement] = [
            string(.realWorldValueLUTLabel, vr: .SH, label),
            fd(.realWorldValueIntercept, [intercept]),
            fd(.realWorldValueSlope, [slope]),
            sequence(.measurementUnitsCodeSequence, [codedConceptDataSet(units)]),
            sequence(.quantityDefinitionSequence, [
                DicomDataSet(elements: [
                    string(.valueType, vr: .CS, "CODE"),
                    sequence(.conceptNameCodeSequence, [codedConceptDataSet(quantityName)]),
                    sequence(.conceptCodeSequence, [codedConceptDataSet(quantityCode)])
                ])
            ])
        ]
        if let first {
            elements.append(us(.realWorldValueFirstValueMapped, first))
        }
        if let last {
            elements.append(us(.realWorldValueLastValueMapped, last))
        }
        if let doubleFirst {
            elements.append(fd(.doubleFloatRealWorldValueFirstValueMapped, [doubleFirst]))
        }
        if let doubleLast {
            elements.append(fd(.doubleFloatRealWorldValueLastValueMapped, [doubleLast]))
        }
        return DicomDataSet(elements: elements)
    }

    private func frameFunctionalGroup(
        index: Int,
        z: Double,
        sourceReference: DicomSourceImageReference
    ) -> DicomDataSet {
        DicomDataSet(elements: [
            sequence(.frameContentSequence, [
                DicomDataSet(elements: [
                    ul(.dimensionIndexValues, [index + 1]),
                    string(.stackID, vr: .SH, "PM"),
                    ul(.inStackPositionNumber, [index + 1])
                ])
            ]),
            sequence(.planePositionSequence, [
                DicomDataSet(elements: [
                    ds(.imagePositionPatient, ["0", "0", String(z)])
                ])
            ]),
            sequence(.derivationImageSequence, [
                DicomDataSet(elements: [
                    sequence(.sourceImageSequence, [sourceImageDataSet(sourceReference)])
                ])
            ])
        ])
    }

    private func sourceImageDataSet(_ reference: DicomSourceImageReference) -> DicomDataSet {
        var elements: [DicomDataElement] = []
        if let sopClassUID = reference.referencedSOPClassUID {
            elements.append(string(.referencedSOPClassUID, vr: .UI, sopClassUID))
        }
        if let sopInstanceUID = reference.referencedSOPInstanceUID {
            elements.append(string(.referencedSOPInstanceUID, vr: .UI, sopInstanceUID))
        }
        if !reference.referencedFrameNumbers.isEmpty {
            elements.append(DicomDataElement(
                tag: DicomTag.referencedFrameNumber.rawValue,
                vr: .IS,
                value: .strings(reference.referencedFrameNumbers.map(String.init))
            ))
        }
        return DicomDataSet(elements: elements)
    }

    private func codedConceptDataSet(_ concept: DicomCodedConcept) -> DicomDataSet {
        var elements = [
            string(.codeValue, vr: .SH, concept.codeValue),
            string(.codingSchemeDesignator, vr: .SH, concept.codingSchemeDesignator)
        ]
        if let meaning = concept.codeMeaning {
            elements.append(string(.codeMeaning, vr: .LO, meaning))
        }
        return DicomDataSet(elements: elements)
    }

    private func sequence(_ tag: DicomTag, _ dataSets: [DicomDataSet]) -> DicomDataElement {
        DicomDataElement(
            tag: tag.rawValue,
            vr: .SQ,
            value: .sequence(dataSets.map { DicomSequenceItem(dataSet: $0) })
        )
    }

    private func string(_ tag: DicomTag, vr: DicomVR, _ value: String) -> DicomDataElement {
        DicomDataElement(tag: tag.rawValue, vr: vr, value: .strings([value]))
    }

    private func us(_ tag: DicomTag, _ value: Int) -> DicomDataElement {
        DicomDataElement(tag: tag.rawValue, vr: .US, value: .unsignedIntegers([UInt(value)]))
    }

    private func ul(_ tag: DicomTag, _ values: [Int]) -> DicomDataElement {
        DicomDataElement(tag: tag.rawValue, vr: .UL, value: .unsignedIntegers(values.map { UInt($0) }))
    }

    private func ds(_ tag: DicomTag, _ values: [String]) -> DicomDataElement {
        DicomDataElement(tag: tag.rawValue, vr: .DS, value: .strings(values))
    }

    private func fd(_ tag: DicomTag, _ values: [Double]) -> DicomDataElement {
        DicomDataElement(tag: tag.rawValue, vr: .FD, value: .floats(values))
    }

    private func bytes(_ tag: DicomTag, vr: DicomVR, _ data: Data) -> DicomDataElement {
        DicomDataElement(tag: tag.rawValue, vr: vr, value: .bytes(data))
    }

    private func uint16Data(_ values: [UInt16]) -> Data {
        values.reduce(into: Data()) { data, value in
            data.append(UInt8(value & 0x00FF))
            data.append(UInt8((value >> 8) & 0x00FF))
        }
    }

    private func assertEqual(
        _ actual: [Double],
        _ expected: [Double],
        accuracy: Double,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(actual.count, expected.count, file: file, line: line)
        for (actualValue, expectedValue) in zip(actual, expected) {
            XCTAssertEqual(actualValue, expectedValue, accuracy: accuracy, file: file, line: line)
        }
    }
}
