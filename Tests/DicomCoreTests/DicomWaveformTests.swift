import XCTest
@testable import DicomCore

final class DicomWaveformTests: XCTestCase {
    func testSyntheticECGWaveformRoundTripsChannelsSamplingUnitsAndReferences() throws {
        let microvolt = DicomCodedConcept(codeValue: "uV", codingSchemeDesignator: "UCUM", codeMeaning: "microvolt")
        let sourceReference = DicomWaveformSourceReference(
            referencedSOPClassUID: "1.2.840.10008.5.1.4.1.1.2",
            referencedSOPInstanceUID: "2.25.9404",
            referencedWaveformChannels: [DicomWaveformChannelReference(multiplexGroupNumber: 1, channelNumber: 1)]
        )
        let group = DicomWaveformMultiplexGroup(
            label: "REST",
            samplingFrequency: 500,
            timeOffsetMilliseconds: 12.5,
            triggerTimeOffsetMilliseconds: -2,
            triggerSamplePosition: 2,
            sampleInterpretation: .signed16,
            waveformDataDisplayScale: 25,
            channels: [
                DicomWaveformChannel(
                    number: 1,
                    label: "I",
                    status: ["OK"],
                    source: DicomCodedConcept(
                        codeValue: "MDC_ECG_LEAD_I",
                        codingSchemeDesignator: "MDC",
                        codeMeaning: "Lead I"
                    ),
                    sourceWaveformReferences: [sourceReference],
                    sensitivity: 4.88,
                    sensitivityUnits: microvolt,
                    baseline: 0,
                    bitsStored: 16,
                    lowFrequency: 0.05,
                    highFrequency: 150,
                    notchFrequency: 60,
                    samples: [100, 104, 98, 110]
                ),
                DicomWaveformChannel(
                    number: 2,
                    label: "II",
                    source: DicomCodedConcept(
                        codeValue: "MDC_ECG_LEAD_II",
                        codingSchemeDesignator: "MDC",
                        codeMeaning: "Lead II"
                    ),
                    sensitivity: 4.88,
                    sensitivityUnits: microvolt,
                    bitsStored: 16,
                    samples: [-10, -12, -8, -6]
                )
            ]
        )

        let decoder = try open(
            groups: [group],
            options: DicomWaveformBuildOptions(
                kind: .twelveLeadECG,
                sopInstanceUID: "2.25.9400",
                studyInstanceUID: "2.25.9401",
                seriesInstanceUID: "2.25.9402",
                patientName: "Waveform^Patient",
                patientID: "ECG-1",
                studyID: "ECG-STUDY",
                studyDate: "20260528",
                studyTime: "160000",
                seriesNumber: 3,
                instanceNumber: 1,
                seriesDate: "20260528",
                seriesTime: "160100",
                seriesDescription: "Synthetic ECG",
                contentDate: "20260528",
                contentTime: "160200"
            )
        )
        let waveform = try XCTUnwrap(decoder.waveform)
        let decodedGroup = try XCTUnwrap(waveform.multiplexGroups.first)
        let decodedLeadI = try XCTUnwrap(decodedGroup.channels.first)
        let decodedLeadII = try XCTUnwrap(decodedGroup.channels.dropFirst().first)

        XCTAssertEqual(waveform.kind, .twelveLeadECG)
        XCTAssertEqual(waveform.sopClassUID, DicomWaveform.twelveLeadECGWaveformStorageSOPClassUID)
        XCTAssertEqual(waveform.sopInstanceUID, "2.25.9400")
        XCTAssertEqual(waveform.studyInstanceUID, "2.25.9401")
        XCTAssertEqual(waveform.seriesInstanceUID, "2.25.9402")
        XCTAssertEqual(waveform.modality, "ECG")
        XCTAssertEqual(waveform.patientName?.familyName, "Waveform")
        XCTAssertEqual(waveform.patientID, "ECG-1")
        XCTAssertEqual(waveform.totalChannelCount, 2)

        XCTAssertEqual(decodedGroup.label, "REST")
        XCTAssertEqual(decodedGroup.samplingFrequency, 500)
        XCTAssertEqual(decodedGroup.timeOffsetMilliseconds, 12.5)
        XCTAssertEqual(decodedGroup.triggerTimeOffsetMilliseconds, -2)
        XCTAssertEqual(decodedGroup.triggerSamplePosition, 2)
        XCTAssertEqual(decodedGroup.sampleInterpretation, .signed16)
        XCTAssertEqual(decodedGroup.waveformDataDisplayScale, 25)
        XCTAssertEqual(decodedGroup.numberOfSamples, 4)

        XCTAssertEqual(decodedLeadI.number, 1)
        XCTAssertEqual(decodedLeadI.label, "I")
        XCTAssertEqual(decodedLeadI.status, ["OK"])
        XCTAssertEqual(decodedLeadI.source?.codeValue, "MDC_ECG_LEAD_I")
        XCTAssertEqual(decodedLeadI.sensitivity, 4.88)
        XCTAssertEqual(decodedLeadI.sensitivityUnits, microvolt)
        XCTAssertEqual(decodedLeadI.bitsStored, 16)
        XCTAssertEqual(decodedLeadI.lowFrequency, 0.05)
        XCTAssertEqual(decodedLeadI.highFrequency, 150)
        XCTAssertEqual(decodedLeadI.notchFrequency, 60)
        XCTAssertEqual(decodedLeadI.samples, [100, 104, 98, 110])
        XCTAssertEqual(decodedLeadI.sourceWaveformReferences, [sourceReference])
        XCTAssertEqual(decodedLeadI.physicalValue(for: 100), 488)

        XCTAssertEqual(decodedLeadII.number, 2)
        XCTAssertEqual(decodedLeadII.label, "II")
        XCTAssertEqual(decodedLeadII.source?.codeValue, "MDC_ECG_LEAD_II")
        XCTAssertEqual(decodedLeadII.samples, [-10, -12, -8, -6])
    }

    func testBuilderRejectsInconsistentChannelSampleCounts() throws {
        let group = DicomWaveformMultiplexGroup(
            samplingFrequency: 250,
            channels: [
                DicomWaveformChannel(label: "I", samples: [1, 2, 3]),
                DicomWaveformChannel(label: "II", samples: [1, 2])
            ]
        )

        XCTAssertThrowsError(try DicomWaveformBuilder.part10Data(multiplexGroups: [group])) { error in
            XCTAssertEqual(error as? DicomWaveformError, .inconsistentSampleCounts(group: nil))
        }
    }

    func testBuilderRejectsOutOfRangeSamplesForInterpretation() throws {
        let group = DicomWaveformMultiplexGroup(
            samplingFrequency: 250,
            sampleInterpretation: .signed8,
            channels: [DicomWaveformChannel(label: "I", samples: [0, 128])]
        )

        XCTAssertThrowsError(try DicomWaveformBuilder.part10Data(multiplexGroups: [group])) { error in
            XCTAssertEqual(error as? DicomWaveformError, .sampleOutOfRange(value: 128, interpretation: "SB"))
        }
    }

    func testWaveformRoundTripsImplicitVRLittleEndian() throws {
        let group = DicomWaveformMultiplexGroup(
            samplingFrequency: 250,
            channels: [
                DicomWaveformChannel(label: "I", samples: [1, 2, 3]),
                DicomWaveformChannel(label: "II", samples: [-1, -2, -3])
            ]
        )
        let dataSet = try DicomWaveformBuilder.dataSet(
            multiplexGroups: [group],
            options: DicomWaveformBuildOptions(
                sopInstanceUID: "2.25.9410",
                studyInstanceUID: "2.25.9411",
                seriesInstanceUID: "2.25.9412"
            )
        )
        let data = try DicomDataSetWriter.part10Data(
            from: dataSet,
            options: DicomPart10WriterOptions(
                transferSyntax: .implicitVRLittleEndian,
                mediaStorageSOPClassUID: dataSet.string(for: .sopClassUID),
                mediaStorageSOPInstanceUID: dataSet.string(for: .sopInstanceUID)
            )
        )

        let waveform = try XCTUnwrap(open(data: data).waveform)
        let decodedGroup = try XCTUnwrap(waveform.multiplexGroups.first)

        XCTAssertEqual(decodedGroup.sampleInterpretation, .signed16)
        XCTAssertEqual(decodedGroup.channels.map(\.samples), [[1, 2, 3], [-1, -2, -3]])
    }

    func testWaveformScopeListsSupportedStorageKindsAndSampleInterpretations() throws {
        XCTAssertEqual(
            DicomWaveformStorageKind.allCases.map(\.storageSOPClassUID),
            [
                DicomWaveform.twelveLeadECGWaveformStorageSOPClassUID,
                DicomWaveform.generalECGWaveformStorageSOPClassUID,
                DicomWaveform.ambulatoryECGWaveformStorageSOPClassUID,
                DicomWaveform.general32BitECGWaveformStorageSOPClassUID,
                DicomWaveform.hemodynamicWaveformStorageSOPClassUID,
                DicomWaveform.cardiacElectrophysiologyWaveformStorageSOPClassUID,
                DicomWaveform.arterialPulseWaveformStorageSOPClassUID,
                DicomWaveform.respiratoryWaveformStorageSOPClassUID
            ]
        )
        XCTAssertEqual(
            DicomWaveformSampleInterpretation.allCases.map(\.rawValue),
            ["SB", "UB", "SS", "US", "SL", "UL"]
        )

        let matrixRow = try XCTUnwrap(DicomExportSupportMatrix.packageDefault.row(feature: "Waveform"))
        XCTAssertTrue(matrixRow.requiredTags.contains("Waveform Sequence"))
        XCTAssertTrue(matrixRow.unsupportedCases.contains("Float/double samples"))
        XCTAssertTrue(matrixRow.typedFailure.contains("DicomWaveformError"))
    }

    func testSeriesLoaderSkipsWaveformAsNonImageVolumeInput() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("waveform_series_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let url = directory.appendingPathComponent("waveform.dcm")
        try DicomWaveformBuilder.write(
            multiplexGroups: [
                DicomWaveformMultiplexGroup(
                    samplingFrequency: 500,
                    channels: [DicomWaveformChannel(label: "I", samples: [1, 2, 3])]
                )
            ],
            to: url,
            options: DicomWaveformBuildOptions(seriesDescription: "Not a volume")
        )

        XCTAssertThrowsError(try DicomSeriesLoader().loadSeries(in: directory)) { error in
            guard case DicomSeriesLoaderError.noDicomFiles = error else {
                return XCTFail("Expected noDicomFiles after skipping Waveform, got \(error)")
            }
        }
    }

    private func open(
        groups: [DicomWaveformMultiplexGroup],
        options: DicomWaveformBuildOptions
    ) throws -> DCMDecoder {
        let data = try DicomWaveformBuilder.part10Data(multiplexGroups: groups, options: options)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("waveform_\(UUID().uuidString).dcm")
        try data.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        return try DCMDecoder(contentsOf: url)
    }

    private func open(data: Data) throws -> DCMDecoder {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("waveform_implicit_\(UUID().uuidString).dcm")
        try data.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        return try DCMDecoder(contentsOf: url)
    }
}
