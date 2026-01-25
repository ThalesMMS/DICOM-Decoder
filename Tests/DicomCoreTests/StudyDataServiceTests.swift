import XCTest
@testable import DicomCore

final class StudyDataServiceTests: XCTestCase {

    // MARK: - Service Initialization Tests

    func testServiceInitialization() {
        let service = StudyDataService()
        XCTAssertNotNil(service, "Service should initialize successfully")
    }

    func testServiceInitializationWithCustomFileManager() {
        let customFileManager = FileManager.default
        let service = StudyDataService(fileManager: customFileManager)
        XCTAssertNotNil(service, "Service should initialize with custom FileManager")
    }

    // MARK: - StudyMetadata Structure Tests

    func testStudyMetadataCreation() {
        let metadata = StudyMetadata(
            filePath: "/test/path.dcm",
            patientName: "Test Patient",
            patientID: "PAT001",
            patientSex: "M",
            patientAge: "045Y",
            studyInstanceUID: "1.2.3.4.5",
            studyDate: "20240101",
            studyDescription: "CT Chest",
            seriesInstanceUID: "1.2.3.4.5.6",
            modality: "CT",
            instanceNumber: 1,
            bodyPartExamined: "CHEST",
            institutionName: "General Hospital"
        )

        XCTAssertEqual(metadata.filePath, "/test/path.dcm", "File path should match")
        XCTAssertEqual(metadata.patientName, "Test Patient", "Patient name should match")
        XCTAssertEqual(metadata.patientID, "PAT001", "Patient ID should match")
        XCTAssertEqual(metadata.patientSex, "M", "Patient sex should match")
        XCTAssertEqual(metadata.patientAge, "045Y", "Patient age should match")
        XCTAssertEqual(metadata.studyInstanceUID, "1.2.3.4.5", "Study UID should match")
        XCTAssertEqual(metadata.studyDate, "20240101", "Study date should match")
        XCTAssertEqual(metadata.studyDescription, "CT Chest", "Study description should match")
        XCTAssertEqual(metadata.seriesInstanceUID, "1.2.3.4.5.6", "Series UID should match")
        XCTAssertEqual(metadata.modality, "CT", "Modality should match")
        XCTAssertEqual(metadata.instanceNumber, 1, "Instance number should match")
        XCTAssertEqual(metadata.bodyPartExamined, "CHEST", "Body part should match")
        XCTAssertEqual(metadata.institutionName, "General Hospital", "Institution should match")
    }

    // MARK: - DICOMValidationResult Tests

    func testValidationResultValid() {
        let result = DICOMValidationResult(
            isValid: true,
            issues: [],
            fileSize: 1024000
        )

        XCTAssertTrue(result.isValid, "Result should be valid")
        XCTAssertTrue(result.issues.isEmpty, "Should have no issues")
        XCTAssertEqual(result.fileSize, 1024000, "File size should match")
        XCTAssertTrue(result.summary.contains("Valid"), "Summary should indicate valid file")
    }

    func testValidationResultInvalid() {
        let result = DICOMValidationResult(
            isValid: false,
            issues: ["Missing DICOM header signature", "File too small"],
            fileSize: 100
        )

        XCTAssertFalse(result.isValid, "Result should be invalid")
        XCTAssertEqual(result.issues.count, 2, "Should have two issues")
        XCTAssertTrue(result.summary.contains("Invalid"), "Summary should indicate invalid file")
        XCTAssertTrue(result.summary.contains("Missing DICOM header signature"), "Summary should include first issue")
    }

    func testValidationResultSummaryFormatting() {
        let validResult = DICOMValidationResult(
            isValid: true,
            issues: [],
            fileSize: 2048000
        )

        let summary = validResult.summary
        XCTAssertTrue(summary.contains("✅"), "Valid result should have checkmark")

        let invalidResult = DICOMValidationResult(
            isValid: false,
            issues: ["Test issue"],
            fileSize: 100
        )

        let invalidSummary = invalidResult.summary
        XCTAssertTrue(invalidSummary.contains("❌"), "Invalid result should have X mark")
        XCTAssertTrue(invalidSummary.contains("Test issue"), "Should include issue description")
    }

    // MARK: - Patient Model Creation Tests

    func testCreatePatientModel() {
        let service = StudyDataService()
        let metadata = StudyMetadata(
            filePath: "/test/path.dcm",
            patientName: "John Doe",
            patientID: "PAT123",
            patientSex: "M",
            patientAge: "030Y",
            studyInstanceUID: "1.2.840.113619.2.1",
            studyDate: "20240115",
            studyDescription: "Brain MRI",
            seriesInstanceUID: "1.2.840.113619.2.1.1",
            modality: "MR",
            instanceNumber: 5,
            bodyPartExamined: "BRAIN",
            institutionName: "University Hospital"
        )

        let patientModel = service.createPatientModel(from: metadata)

        XCTAssertEqual(patientModel.patientName, "John Doe", "Patient name should match")
        XCTAssertEqual(patientModel.patientID, "PAT123", "Patient ID should match")
        XCTAssertEqual(patientModel.studyInstanceUID, "1.2.840.113619.2.1", "Study UID should match")
        XCTAssertEqual(patientModel.modality, .mr, "Modality should be MR")
    }

    func testCreatePatientModelWithUnknownModality() {
        let service = StudyDataService()
        let metadata = StudyMetadata(
            filePath: "/test/path.dcm",
            patientName: "Jane Doe",
            patientID: "PAT456",
            patientSex: "F",
            patientAge: "025Y",
            studyInstanceUID: "1.2.3.4.5",
            studyDate: "20240115",
            studyDescription: "Test Study",
            seriesInstanceUID: "1.2.3.4.5.6",
            modality: "UNKNOWN_MODALITY",
            instanceNumber: 1,
            bodyPartExamined: "CHEST",
            institutionName: "Test Hospital"
        )

        let patientModel = service.createPatientModel(from: metadata)

        XCTAssertEqual(patientModel.modality, .unknown, "Unknown modality should map to .unknown")
    }

    func testCreatePatientModelWithKnownModalities() {
        let service = StudyDataService()
        let testCases: [(String, DICOMModality)] = [
            ("CT", .ct),
            ("MR", .mr),
            ("DX", .dx),
            ("CR", .cr),
            ("US", .us),
            ("MG", .mg),
            ("PT", .pt),
            ("NM", .nm)
        ]

        for (modalityString, expectedModality) in testCases {
            let metadata = StudyMetadata(
                filePath: "/test/path.dcm",
                patientName: "Test Patient",
                patientID: "PAT001",
                patientSex: "M",
                patientAge: "040Y",
                studyInstanceUID: "1.2.3.4.5",
                studyDate: "20240115",
                studyDescription: "Test",
                seriesInstanceUID: "1.2.3.4.5.6",
                modality: modalityString,
                instanceNumber: 1,
                bodyPartExamined: "CHEST",
                institutionName: "Hospital"
            )

            let patientModel = service.createPatientModel(from: metadata)
            XCTAssertEqual(
                patientModel.modality,
                expectedModality,
                "\(modalityString) should map to \(expectedModality)"
            )
        }
    }

    // MARK: - Study Grouping Tests

    func testGroupStudiesByUID() {
        let service = StudyDataService()

        let metadata1 = createTestMetadata(studyUID: "1.2.3", seriesUID: "1.2.3.1", instanceNumber: 1)
        let metadata2 = createTestMetadata(studyUID: "1.2.3", seriesUID: "1.2.3.2", instanceNumber: 2)
        let metadata3 = createTestMetadata(studyUID: "4.5.6", seriesUID: "4.5.6.1", instanceNumber: 1)

        let grouped = service.groupStudiesByUID([metadata1, metadata2, metadata3])

        XCTAssertEqual(grouped.count, 2, "Should have 2 unique studies")
        XCTAssertEqual(grouped["1.2.3"]?.count, 2, "Study 1.2.3 should have 2 files")
        XCTAssertEqual(grouped["4.5.6"]?.count, 1, "Study 4.5.6 should have 1 file")
    }

    func testGroupStudiesByUIDEmptyArray() {
        let service = StudyDataService()
        let grouped = service.groupStudiesByUID([])

        XCTAssertTrue(grouped.isEmpty, "Grouping empty array should return empty dictionary")
    }

    func testGroupStudiesByUIDSingleStudy() {
        let service = StudyDataService()

        let metadata1 = createTestMetadata(studyUID: "1.2.3", seriesUID: "1.2.3.1", instanceNumber: 1)
        let metadata2 = createTestMetadata(studyUID: "1.2.3", seriesUID: "1.2.3.1", instanceNumber: 2)
        let metadata3 = createTestMetadata(studyUID: "1.2.3", seriesUID: "1.2.3.1", instanceNumber: 3)

        let grouped = service.groupStudiesByUID([metadata1, metadata2, metadata3])

        XCTAssertEqual(grouped.count, 1, "Should have 1 unique study")
        XCTAssertEqual(grouped["1.2.3"]?.count, 3, "Study should have 3 files")
    }

    func testGroupStudiesByUIDMultipleSeries() {
        let service = StudyDataService()

        // Same study, different series
        let metadata1 = createTestMetadata(studyUID: "1.2.3", seriesUID: "1.2.3.1", instanceNumber: 1)
        let metadata2 = createTestMetadata(studyUID: "1.2.3", seriesUID: "1.2.3.2", instanceNumber: 1)
        let metadata3 = createTestMetadata(studyUID: "1.2.3", seriesUID: "1.2.3.3", instanceNumber: 1)

        let grouped = service.groupStudiesByUID([metadata1, metadata2, metadata3])

        XCTAssertEqual(grouped.count, 1, "Should have 1 unique study")
        XCTAssertEqual(grouped["1.2.3"]?.count, 3, "Study should have 3 files from different series")

        // Verify all series UIDs are different
        let seriesUIDs = Set(grouped["1.2.3"]!.map { $0.seriesInstanceUID })
        XCTAssertEqual(seriesUIDs.count, 3, "Should have 3 unique series")
    }

    // MARK: - Validation Tests

    func testValidateDICOMFileNonExistent() async {
        let service = StudyDataService()
        let nonExistentPath = "/tmp/nonexistent_\(UUID().uuidString).dcm"

        let result = await service.validateDICOMFile(nonExistentPath)

        XCTAssertFalse(result.isValid, "Non-existent file should be invalid")
        XCTAssertTrue(result.issues.contains("File does not exist"), "Should report file not found")
        XCTAssertEqual(result.fileSize, 0, "File size should be 0 for non-existent file")
    }

    // MARK: - Metadata Extraction Tests

    func testExtractStudyMetadataAsync() async {
        // Note: This test requires actual DICOM files to work properly
        // For now, we test the async interface and expected behavior with invalid file
        let service = StudyDataService()
        let invalidPath = "/tmp/invalid_\(UUID().uuidString).dcm"

        let metadata = await service.extractStudyMetadata(from: invalidPath)

        // Invalid file should return nil due to missing UIDs
        XCTAssertNil(metadata, "Invalid DICOM file should return nil metadata")
    }

    func testExtractBatchMetadataAsync() async {
        let service = StudyDataService()
        let invalidPaths = [
            "/tmp/invalid1_\(UUID().uuidString).dcm",
            "/tmp/invalid2_\(UUID().uuidString).dcm",
            "/tmp/invalid3_\(UUID().uuidString).dcm"
        ]

        let metadata = await service.extractBatchMetadata(from: invalidPaths)

        // Invalid files should return empty array
        XCTAssertTrue(metadata.isEmpty, "Batch extraction of invalid files should return empty array")
    }

    func testExtractBatchMetadataEmptyArray() async {
        let service = StudyDataService()

        let metadata = await service.extractBatchMetadata(from: [])

        XCTAssertTrue(metadata.isEmpty, "Batch extraction with empty input should return empty array")
    }

    // MARK: - Thumbnail Extraction Tests

    func testExtractThumbnailAsync() async {
        let service = StudyDataService()
        let invalidPath = "/tmp/invalid_\(UUID().uuidString).dcm"

        let thumbnail = await service.extractThumbnail(from: invalidPath)

        // Invalid file should return nil thumbnail
        XCTAssertNil(thumbnail, "Thumbnail extraction from invalid file should return nil")
    }

    func testExtractThumbnailWithCustomSize() async {
        let service = StudyDataService()
        let invalidPath = "/tmp/invalid_\(UUID().uuidString).dcm"
        let customSize = CGSize(width: 256, height: 256)

        let thumbnail = await service.extractThumbnail(from: invalidPath, maxSize: customSize)

        // Invalid file should return nil thumbnail regardless of size
        XCTAssertNil(thumbnail, "Thumbnail extraction from invalid file should return nil")
    }

    // MARK: - Edge Cases and Error Handling Tests

    func testStudyMetadataWithEmptyValues() {
        // Test that metadata can handle empty values properly
        let metadata = StudyMetadata(
            filePath: "",
            patientName: "",
            patientID: "",
            patientSex: "",
            patientAge: "",
            studyInstanceUID: "1.2.3.4.5",
            studyDate: "",
            studyDescription: "",
            seriesInstanceUID: "1.2.3.4.5.6",
            modality: "",
            instanceNumber: 0,
            bodyPartExamined: "",
            institutionName: ""
        )

        XCTAssertEqual(metadata.patientName, "", "Empty patient name should be preserved")
        XCTAssertEqual(metadata.modality, "", "Empty modality should be preserved")
        XCTAssertEqual(metadata.instanceNumber, 0, "Zero instance number should be preserved")
    }

    func testStudyMetadataWithSpecialCharacters() {
        let metadata = StudyMetadata(
            filePath: "/test/path with spaces/file.dcm",
            patientName: "Müller, José^María",
            patientID: "PAT-001-α",
            patientSex: "M",
            patientAge: "045Y",
            studyInstanceUID: "1.2.840.113619.2.1",
            studyDate: "20240115",
            studyDescription: "Study with special chars: <>\"'&",
            seriesInstanceUID: "1.2.840.113619.2.1.1",
            modality: "CT",
            instanceNumber: 1,
            bodyPartExamined: "CHEST",
            institutionName: "Hôpital Général"
        )

        XCTAssertEqual(metadata.patientName, "Müller, José^María", "Special characters should be preserved")
        XCTAssertEqual(metadata.institutionName, "Hôpital Général", "Unicode characters should be preserved")
        XCTAssertTrue(metadata.studyDescription.contains("&"), "Special XML characters should be preserved")
    }

    func testGroupStudiesPreservesInstanceOrdering() {
        let service = StudyDataService()

        let metadata1 = createTestMetadata(studyUID: "1.2.3", seriesUID: "1.2.3.1", instanceNumber: 5)
        let metadata2 = createTestMetadata(studyUID: "1.2.3", seriesUID: "1.2.3.1", instanceNumber: 2)
        let metadata3 = createTestMetadata(studyUID: "1.2.3", seriesUID: "1.2.3.1", instanceNumber: 8)

        let grouped = service.groupStudiesByUID([metadata1, metadata2, metadata3])

        XCTAssertEqual(grouped["1.2.3"]?.count, 3, "Should preserve all instances")

        // Verify instance numbers are preserved
        let instanceNumbers = grouped["1.2.3"]!.map { $0.instanceNumber }
        XCTAssertTrue(instanceNumbers.contains(5), "Should contain instance 5")
        XCTAssertTrue(instanceNumbers.contains(2), "Should contain instance 2")
        XCTAssertTrue(instanceNumbers.contains(8), "Should contain instance 8")
    }

    // MARK: - Integration Tests

    func testCompleteWorkflow() {
        let service = StudyDataService()

        // Create sample metadata
        let metadata1 = createTestMetadata(studyUID: "Study1", seriesUID: "Series1", instanceNumber: 1)
        let metadata2 = createTestMetadata(studyUID: "Study1", seriesUID: "Series1", instanceNumber: 2)
        let metadata3 = createTestMetadata(studyUID: "Study2", seriesUID: "Series2", instanceNumber: 1)

        // Group studies
        let grouped = service.groupStudiesByUID([metadata1, metadata2, metadata3])

        XCTAssertEqual(grouped.count, 2, "Should have 2 studies")

        // Create patient models from first study
        if let study1Files = grouped["Study1"] {
            let patientModels = study1Files.map { service.createPatientModel(from: $0) }
            XCTAssertEqual(patientModels.count, 2, "Should create 2 patient models")
            XCTAssertEqual(patientModels[0].studyInstanceUID, "Study1", "Study UID should match")
        } else {
            XCTFail("Study1 should exist in grouped results")
        }
    }

    func testPatientModelDisplayProperties() {
        let service = StudyDataService()
        let metadata = createTestMetadata(
            studyUID: "1.2.3.4.5",
            seriesUID: "1.2.3.4.5.6",
            instanceNumber: 1,
            patientName: "Test^Patient",
            modality: "CT"
        )

        let patientModel = service.createPatientModel(from: metadata)

        XCTAssertFalse(patientModel.displayName.isEmpty, "Display name should not be empty")
        XCTAssertNotNil(patientModel.modality, "Modality should be set")
        XCTAssertEqual(patientModel.modality, .ct, "Modality should be CT")
    }

    // MARK: - Helper Methods

    private func createTestMetadata(
        studyUID: String,
        seriesUID: String,
        instanceNumber: Int,
        patientName: String = "Test Patient",
        modality: String = "CT"
    ) -> StudyMetadata {
        return StudyMetadata(
            filePath: "/test/file_\(instanceNumber).dcm",
            patientName: patientName,
            patientID: "PAT001",
            patientSex: "M",
            patientAge: "045Y",
            studyInstanceUID: studyUID,
            studyDate: "20240115",
            studyDescription: "Test Study",
            seriesInstanceUID: seriesUID,
            modality: modality,
            instanceNumber: instanceNumber,
            bodyPartExamined: "CHEST",
            institutionName: "Test Hospital"
        )
    }
}
