//
//  SeriesBusinessLogic.swift
//
//  Business logic service for Series operations (series selection screen)
//

import Foundation
import Combine
import OSLog

// MARK: - DICOM Tag Constants
private let SERIES_INSTANCE_UID: Int = 0x0020000E
private let SERIES_NUMBER: Int = 0x00200011
private let SERIES_DESCRIPTION: Int = 0x0008103E
private let MODALITY: Int = 0x00080060
private let INSTANCE_NUMBER: Int = 0x00200013

// MARK: - ⚠️ MIGRATION STATUS: NEW FILE
// Migration date: December 3, 2024
// New location: DICOMViewer/Services/SeriesBusinessLogic.swift
// Status: Business logic extracted from SwiftSeriesViewController
// TODO: Integrate with SeriesViewModel after validation

// MARK: - Business Logic Service

final class SeriesBusinessLogic: ObservableObject, Sendable {
    
    // MARK: - Properties
    
    private let logger = Logger(subsystem: "com.dicomviewer", category: "SeriesBL")
    private nonisolated(unsafe) let fileManager: FileManager
    private let studyDataService: StudyDataService
    
    // MARK: - Initialization
    
    init(
        fileManager: FileManager = .default,
        studyDataService: StudyDataService = StudyDataService()
    ) {
        self.fileManager = fileManager
        self.studyDataService = studyDataService
        logger.info("📊 SeriesBusinessLogic initialized - handles Series data processing")
    }
    
    // MARK: - Public Interface
    
    /// Process study files and organize into series - now with caching support
    func processSeriesInformation(from filePaths: [String], studyUID: String? = nil) async -> Result<[SeriesInfo], DICOMError> {
        logger.info("🔍 Processing series (\(filePaths.count) files provided, studyUID: \(studyUID ?? "unknown"))...")
        
        // If we have a studyUID, check cache first
        if let studyUID = studyUID {
            logger.info("📋 Checking cache for study \(studyUID)...")
            let cachedSeries = await StudyManager.shared.getSeries(for: studyUID)
            
            if !cachedSeries.isEmpty {
                logger.info("✅ Found \(cachedSeries.count) cached series for study")
                
                // Convert cached series to SeriesInfo
                let seriesInfoList = cachedSeries.map { cached -> SeriesInfo in
                    // Convert relative paths to absolute if needed
                    let absolutePaths = cached.filePaths.map { path -> String in
                        if path.hasPrefix("/") {
                            return path // Already absolute
                        }
                        // Convert relative to absolute
                        if let appSupportURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
                            let studiesURL = appSupportURL.appendingPathComponent("Studies")
                            return studiesURL.appendingPathComponent(path).path
                        }
                        return path
                    }
                    
                    return SeriesInfo(
                        seriesInstanceUID: cached.seriesInstanceUID,
                        seriesNumber: cached.seriesNumber,
                        seriesDescription: cached.seriesDescription,
                        modality: cached.modality,
                        numberOfImages: cached.imageCount,
                        filePaths: absolutePaths,
                        thumbnailPath: absolutePaths.count > 0 ? absolutePaths[absolutePaths.count / 2] : nil
                    )
                }
                
                return .success(seriesInfoList)
            } else {
                logger.info("📋 No cached series found, processing files...")
            }
        }
        
        // Fall back to processing files if no cache or no studyUID
        logger.info("🔍 Processing \(filePaths.count) files to identify series...")
        
        // 1. Extract metadata and organize by series UID
        let (seriesMap, seriesMetadata) = await extractSeriesMetadata(from: filePaths)
        
        if seriesMap.isEmpty {
            logger.info("ℹ️ No valid DICOM series found")
            return .success([])
        }
        
        // 2. Create SeriesInfo objects with sorted files
        let seriesObjects = await createSeriesObjects(from: seriesMap, metadata: seriesMetadata)
        
        // 3. Sort series by series number or display title
        let sortedSeries = sortSeries(seriesObjects)
        
        logger.info("✅ Successfully processed \(sortedSeries.count) series")
        return .success(sortedSeries)
    }
    
    /// Validate file paths and normalize them
    func validateAndNormalizePaths(_ filePaths: [String]) async -> [String] {
        let documentsPath = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true)[0]
        
        var validPaths: [String] = []
        
        for filePath in filePaths {
            let normalizedPath: String
            if filePath.hasPrefix("/") {
                // Already absolute path
                normalizedPath = filePath
            } else {
                // Relative path, reconstruct properly
                normalizedPath = (documentsPath as NSString).appendingPathComponent(filePath)
            }
            
            // Verify file exists
            if fileManager.fileExists(atPath: normalizedPath) {
                validPaths.append(normalizedPath)
            } else {
                logger.debug("⚠️ File not found: \(normalizedPath)")
            }
        }
        
        logger.debug("📁 Validated \(validPaths.count)/\(filePaths.count) file paths")
        return validPaths
    }
}

// MARK: - Private Implementation

private extension SeriesBusinessLogic {
    
    /// Extract DICOM metadata and organize by series UID
    func extractSeriesMetadata(from filePaths: [String]) async -> ([String: [String]], [String: SeriesMetadata]) {
        // Validate and normalize paths first
        let validPaths = await validateAndNormalizePaths(filePaths)
        
        var seriesMap: [String: [String]] = [:]
        var seriesMetadata: [String: SeriesMetadata] = [:]
        
        let decoder = DCMDecoder()
        
        for filePath in validPaths {
            decoder.setDicomFilename(filePath)
            
            // Extract series UID
            let seriesUID = decoder.info(for: SERIES_INSTANCE_UID)
            let finalSeriesUID = seriesUID.isEmpty ? "ASSORTED_IMAGES" : seriesUID
            
            // Initialize series if not exists
            if seriesMap[finalSeriesUID] == nil {
                seriesMap[finalSeriesUID] = []
                
                // Extract series metadata
                let seriesNumber = decoder.info(for: SERIES_NUMBER)
                let seriesDescription = decoder.info(for: SERIES_DESCRIPTION)
                let modality = decoder.info(for: MODALITY)
                
                seriesMetadata[finalSeriesUID] = SeriesMetadata(
                    number: seriesNumber.isEmpty ? nil : seriesNumber,
                    description: seriesDescription.isEmpty ? nil : seriesDescription,
                    modality: modality.isEmpty ? nil : modality
                )
            }
            
            // Add file to series
            seriesMap[finalSeriesUID]?.append(filePath)
        }
        
        return (seriesMap, seriesMetadata)
    }
    
    /// Create SeriesInfo objects from metadata
    func createSeriesObjects(from seriesMap: [String: [String]], metadata seriesMetadata: [String: SeriesMetadata]) async -> [SeriesInfo] {
        var seriesObjects: [SeriesInfo] = []
        
        for (seriesUID, filePaths) in seriesMap {
            guard let metadata = seriesMetadata[seriesUID] else { continue }
            
            // Sort files within series by instance number
            let sortedPaths = await sortSeriesFiles(filePaths)
            
            let seriesInfo = SeriesInfo(
                seriesInstanceUID: seriesUID,
                seriesNumber: metadata.number,
                seriesDescription: metadata.description,
                modality: metadata.modality,
                numberOfImages: sortedPaths.count,
                filePaths: sortedPaths,
                thumbnailPath: sortedPaths.first // Use first image as thumbnail
            )
            
            seriesObjects.append(seriesInfo)
        }
        
        return seriesObjects
    }
    
    /// Sort DICOM files within a series by Instance Number
    func sortSeriesFiles(_ paths: [String]) async -> [String] {
        return await withCheckedContinuation { continuation in
            Task.detached(priority: .utility) {
                let decoder = DCMDecoder()
                var sortableItems: [(path: String, instanceNumber: Int?)] = []
                
                for path in paths {
                    decoder.setDicomFilename(path)
                    
                    let instanceStr = decoder.info(for: INSTANCE_NUMBER)
                    let instanceNumber = instanceStr.isEmpty ? nil : Int(instanceStr)
                    
                    sortableItems.append((path: path, instanceNumber: instanceNumber))
                }
                
                // Sort by instance number, with files having instance numbers first
                sortableItems.sort { item1, item2 in
                    if let inst1 = item1.instanceNumber, let inst2 = item2.instanceNumber {
                        return inst1 < inst2
                    }
                    if item1.instanceNumber != nil && item2.instanceNumber == nil {
                        return true
                    }
                    if item1.instanceNumber == nil && item2.instanceNumber != nil {
                        return false
                    }
                    // Both nil - sort by filename
                    return item1.path.localizedStandardCompare(item2.path) == .orderedAscending
                }
                
                let sortedPaths = sortableItems.map { $0.path }
                continuation.resume(returning: sortedPaths)
            }
        }
    }
    
    /// Sort series by series number or display title
    func sortSeries(_ series: [SeriesInfo]) -> [SeriesInfo] {
        return series.sorted { series1, series2 in
            // Try to sort by series number first
            if let num1 = series1.seriesNumber, let num2 = series2.seriesNumber,
               let int1 = Int(num1), let int2 = Int(num2) {
                return int1 < int2
            }
            
            // Fallback to alphabetical sorting by display title
            return series1.displayTitle.localizedStandardCompare(series2.displayTitle) == .orderedAscending
        }
    }
}

// MARK: - Supporting Types

struct SeriesMetadata {
    let number: String?
    let description: String?
    let modality: String?
}