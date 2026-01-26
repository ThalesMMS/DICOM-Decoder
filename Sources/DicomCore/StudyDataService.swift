//
//  StudyDataService.swift
//
//  DICOM data processing service for study metadata extraction and validation
//  Handles low-level DICOM file operations and metadata parsing
//

import Foundation
import OSLog
import CoreGraphics

// MARK: - Study Data Service

public final class StudyDataService: StudyDataServiceProtocol, @unchecked Sendable {

    // MARK: - Properties

    private let logger: AnyLogger
    private let fileManager: FileManager
    private let decoderFactory: () -> DicomDecoderProtocol

    // MARK: - Initialization

    public init(
        fileManager: FileManager = .default,
        decoderFactory: @escaping () -> DicomDecoderProtocol
    ) {
        self.fileManager = fileManager
        self.decoderFactory = decoderFactory
        self.logger = AnyLogger.make(subsystem: "com.dicomviewer", category: "StudyData")
        logger.info("🔬 StudyDataService initialized")
    }
    
    // MARK: - Public Interface
    
    /// Extract comprehensive study metadata from DICOM file
    public func extractStudyMetadata(from filePath: String) async -> StudyMetadata? {
        return await withCheckedContinuation { continuation in
            Task.detached(priority: .utility) {
                let decoder = self.decoderFactory()
                decoder.setDicomFilename(filePath)
                
                // Extract DICOM tag values
                let patientName = decoder.info(for: DicomTag.patientName.rawValue)
                let patientID = decoder.info(for: DicomTag.patientID.rawValue)
                let patientSex = decoder.info(for: DicomTag.patientSex.rawValue)
                let patientAge = decoder.info(for: DicomTag.patientAge.rawValue)
                let studyInstanceUID = decoder.info(for: DicomTag.studyInstanceUID.rawValue)
                let studyDate = decoder.info(for: DicomTag.studyDate.rawValue)
                let studyDescription = decoder.info(for: DicomTag.studyDescription.rawValue)
                let seriesInstanceUID = decoder.info(for: DicomTag.seriesInstanceUID.rawValue)
                let modality = decoder.info(for: DicomTag.modality.rawValue)
                let instanceNumberStr = decoder.info(for: DicomTag.instanceNumber.rawValue)
                let bodyPartExamined = decoder.info(for: DicomTag.bodyPartExamined.rawValue)
                let institutionName = decoder.info(for: DicomTag.institutionName.rawValue)
                
                // Debug logging for metadata extraction
                if studyDate.isEmpty {
                    self.logger.debug("⚠️ Study Date empty for file: \(filePath)")
                }
                if institutionName.isEmpty {
                    self.logger.debug("⚠️ Institution Name empty for file: \(filePath)")
                }
                if patientAge.isEmpty {
                    self.logger.debug("⚠️ Patient Age empty for file: \(filePath)")
                }
                
                // Build metadata with proper fallbacks for empty values
                let metadata = StudyMetadata(
                    filePath: filePath,
                    
                    // Patient Information
                    patientName: patientName.isEmpty ? "Unknown Patient" : patientName,
                    patientID: patientID.isEmpty ? "Unknown ID" : patientID,
                    patientSex: patientSex,
                    patientAge: patientAge.isEmpty ? "Unknown" : patientAge,
                    
                    // Study Information
                    studyInstanceUID: studyInstanceUID,
                    studyDate: studyDate.isEmpty ? "Unknown Date" : studyDate,
                    studyDescription: studyDescription,
                    
                    // Series Information
                    seriesInstanceUID: seriesInstanceUID,
                    modality: modality.isEmpty ? "OT" : modality,
                    
                    // Instance Information
                    instanceNumber: Int(instanceNumberStr) ?? 0,
                    
                    // Additional Information
                    bodyPartExamined: bodyPartExamined,
                    institutionName: institutionName.isEmpty ? "Unknown Location" : institutionName
                )
                
                // Validate essential fields
                guard !metadata.studyInstanceUID.isEmpty,
                      !metadata.seriesInstanceUID.isEmpty else {
                    self.logger.warning("⚠️ Invalid DICOM file: missing required UIDs - \(filePath)")
                    continuation.resume(returning: nil)
                    return
                }
                
                continuation.resume(returning: metadata)
            }
        }
    }
    
    /// Batch extract metadata from multiple files
    public func extractBatchMetadata(from filePaths: [String]) async -> [StudyMetadata] {
        let results = await withTaskGroup(of: StudyMetadata?.self, returning: [StudyMetadata].self) { group in
            for filePath in filePaths {
                group.addTask {
                    await self.extractStudyMetadata(from: filePath)
                }
            }
            
            var metadata: [StudyMetadata] = []
            for await result in group {
                if let meta = result {
                    metadata.append(meta)
                }
            }
            return metadata
        }
        
        logger.info("📊 Extracted metadata from \(results.count)/\(filePaths.count) files")
        return results
    }
    
    /// Validate DICOM file integrity and format
    public func validateDICOMFile(_ filePath: String) async -> DICOMValidationResult {
        return await withCheckedContinuation { continuation in
            Task.detached(priority: .utility) {
                var issues: [String] = []
                
                // 1. Check file existence
                guard self.fileManager.fileExists(atPath: filePath) else {
                    continuation.resume(returning: DICOMValidationResult(
                        isValid: false,
                        issues: ["File does not exist"],
                        fileSize: 0
                    ))
                    return
                }
                
                // 2. Check file size
                guard let attributes = try? self.fileManager.attributesOfItem(atPath: filePath),
                      let fileSize = attributes[.size] as? UInt64 else {
                    issues.append("Could not read file attributes")
                    continuation.resume(returning: DICOMValidationResult(
                        isValid: false,
                        issues: issues,
                        fileSize: 0
                    ))
                    return
                }
                
                // 3. Check minimum DICOM file size
                if fileSize < 132 {
                    issues.append("File too small to be valid DICOM (< 132 bytes)")
                }
                
                // 4. Check DICOM header
                do {
                    let data = try Data(contentsOf: URL(fileURLWithPath: filePath))
                    if data.count > 132 {
                        let dicmBytes = data.subdata(in: 128..<132)
                        if dicmBytes != Data([0x44, 0x49, 0x43, 0x4D]) { // "DICM"
                            issues.append("Missing DICOM header signature")
                        }
                    }
                } catch {
                    issues.append("Could not read file data: \(error.localizedDescription)")
                }
                
                // 5. Try to load with decoder
                let decoder = self.decoderFactory()
                decoder.setDicomFilename(filePath)

                let studyUID = decoder.info(for: DicomTag.studyInstanceUID.rawValue)
                let seriesUID = decoder.info(for: DicomTag.seriesInstanceUID.rawValue)
                
                if studyUID.isEmpty {
                    issues.append("Missing Study Instance UID")
                }
                if seriesUID.isEmpty {
                    issues.append("Missing Series Instance UID")
                }
                
                let result = DICOMValidationResult(
                    isValid: issues.isEmpty,
                    issues: issues,
                    fileSize: fileSize
                )
                
                continuation.resume(returning: result)
            }
        }
    }
    
    /// Create PatientModel from study metadata
    public func createPatientModel(from metadata: StudyMetadata) -> PatientModel {
        let modality = DICOMModality.from(string: metadata.modality)
        
        return PatientModel(
            patientName: metadata.patientName,
            patientID: metadata.patientID,
            studyInstanceUID: metadata.studyInstanceUID,
            modality: modality
        )
    }
    
    /// Group studies by Study Instance UID
    public func groupStudiesByUID(_ metadata: [StudyMetadata]) -> [String: [StudyMetadata]] {
        let grouped = Dictionary(grouping: metadata) { $0.studyInstanceUID }
        
        logger.info("📊 Grouped \(metadata.count) files into \(grouped.count) studies")
        
        // Log study sizes for debugging
        for (studyUID, files) in grouped {
            let uniqueSeries = Set(files.map { $0.seriesInstanceUID }).count
            logger.debug("Study \(studyUID.prefix(8))...: \(files.count) files, \(uniqueSeries) series")
        }
        
        return grouped
    }
    
    /// Extract thumbnail data from DICOM file (first frame)
    public func extractThumbnail(from filePath: String, maxSize: CGSize = CGSize(width: 120, height: 120)) async -> Data? {
        return await withCheckedContinuation { continuation in
            Task.detached(priority: .utility) {
                let decoder = self.decoderFactory()
                decoder.setDicomFilename(filePath)
                
                // Try to get downsampled pixels for thumbnail
                let maxDimension = Int(max(maxSize.width, maxSize.height))
                guard decoder.getDownsampledPixels16(maxDimension: maxDimension) != nil,
                      let width = Int(decoder.info(for: DicomTag.columns.rawValue)),
                      let height = Int(decoder.info(for: DicomTag.rows.rawValue)),
                      width > 0, height > 0 else {
                    self.logger.debug("Could not extract thumbnail from \(filePath)")
                    continuation.resume(returning: nil)
                    return
                }
                
                // Convert pixel data to image data (simplified)
                // This would need proper image conversion logic
                self.logger.debug("📸 Extracted thumbnail from \(filePath): \(width)x\(height)")
                
                // For now, return empty data - proper implementation would convert pixels to PNG/JPEG
                continuation.resume(returning: Data())
            }
        }
    }
}

// MARK: - Supporting Types

public struct StudyMetadata: Sendable {
    // File Information
    let filePath: String
    
    // Patient Information
    let patientName: String
    let patientID: String
    let patientSex: String
    let patientAge: String
    
    // Study Information
    let studyInstanceUID: String
    let studyDate: String
    let studyDescription: String
    
    // Series Information  
    let seriesInstanceUID: String
    let modality: String
    
    // Instance Information
    let instanceNumber: Int
    
    // Additional Information
    let bodyPartExamined: String
    let institutionName: String
}

public struct DICOMValidationResult: Sendable {
    let isValid: Bool
    let issues: [String]
    let fileSize: UInt64
    
    var summary: String {
        if isValid {
            return "✅ Valid DICOM file (\(ByteCountFormatter.string(fromByteCount: Int64(fileSize), countStyle: .file)))"
        } else {
            return "❌ Invalid DICOM file: \(issues.joined(separator: ", "))"
        }
    }
}
