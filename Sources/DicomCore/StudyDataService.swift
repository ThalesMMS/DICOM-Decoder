//
//  StudyDataService.swift
//
//  DICOM data processing service for study metadata extraction and validation
//  Handles low-level DICOM file operations and metadata parsing
//

import Foundation
import OSLog
import CoreGraphics

// MARK: - DICOM Tag Constants (from SwiftMainViewController)
private let PATIENT_ID: Int = 0x00100020
private let PATIENT_NAME: Int = 0x00100010
private let PATIENT_SEX: Int = 0x00100040
private let PATIENT_AGE: Int = 0x00101010
private let STUDY_INSTANCE_UID: Int = 0x0020000d
private let STUDY_DATE: Int = 0x00080020
private let STUDY_DESCRIPTION: Int = 0x00081030
private let MODALITY: Int = 0x00080060
private let SERIES_INSTANCE_UID: Int = 0x0020000e
// MARK: - ⚠️ MIGRATION STATUS: CONSTANTS REFERENCE SwiftMainViewController  
// Migration date: December 3, 2024
// Note: Using constants from SwiftMainViewController to avoid duplication
// TODO: Centralize DICOM constants after full migration

// MARK: - ⚠️ MIGRATION STATUS: NEW FILE
// Migration date: December 3, 2024  
// New location: DICOMViewer/Services/StudyDataService.swift
// Status: DICOM processing logic extracted from SwiftMainViewController
// TODO: Replace direct DCMDecoder usage in SwiftMainViewController

// MARK: - Study Data Service

public final class StudyDataService: Sendable {
    
    // MARK: - Properties
    
    private let logger = Logger(subsystem: "com.dicomviewer", category: "StudyData")
    private nonisolated(unsafe) let fileManager: FileManager
    
    // MARK: - Initialization
    
    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        logger.info("🔬 StudyDataService initialized")
    }
    
    // MARK: - Public Interface
    
    /// Extract comprehensive study metadata from DICOM file
    public func extractStudyMetadata(from filePath: String) async -> StudyMetadata? {
        return await withCheckedContinuation { continuation in
            Task.detached(priority: .utility) {
                let decoder = DCMDecoder()
                decoder.setDicomFilename(filePath)
                
                // Extract DICOM tag values
                let patientName = decoder.info(for: PATIENT_NAME)
                let patientID = decoder.info(for: PATIENT_ID) 
                let patientSex = decoder.info(for: PATIENT_SEX)
                let patientAge = decoder.info(for: PATIENT_AGE)
                let studyInstanceUID = decoder.info(for: STUDY_INSTANCE_UID)
                let studyDate = decoder.info(for: STUDY_DATE)
                let studyDescription = decoder.info(for: STUDY_DESCRIPTION)
                let seriesInstanceUID = decoder.info(for: SERIES_INSTANCE_UID)
                let modality = decoder.info(for: MODALITY)
                let instanceNumberStr = decoder.info(for: 0x00200013)
                let bodyPartExamined = decoder.info(for: 0x00180015)
                let institutionName = decoder.info(for: 0x00080080)
                
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
                let decoder = DCMDecoder()
                decoder.setDicomFilename(filePath)
                
                let studyUID = decoder.info(for: STUDY_INSTANCE_UID)
                let seriesUID = decoder.info(for: SERIES_INSTANCE_UID)
                
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
                let decoder = DCMDecoder()
                decoder.setDicomFilename(filePath)
                
                // Try to get downsampled pixels for thumbnail
                guard decoder.getDownsampledPixels16() != nil,
                      let width = Int(decoder.info(for: 0x00280011)),
                      let height = Int(decoder.info(for: 0x00280010)),
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
