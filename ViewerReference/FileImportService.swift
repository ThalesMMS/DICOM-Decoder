//
//  FileImportService.swift
//
//  Enhanced service for handling file imports including DICOM and ZIP files
//

import UIKit
import Foundation

// MARK: - ⚠️ MIGRATION STATUS: ENHANCED FILE  
// Migration date: December 3, 2024
// Status: Enhanced for MVVM-C - removed singleton, added DI
// TODO: Replace singleton usage in SwiftMainViewController

// MARK: - File Import Service

@MainActor
public final class FileImportService: FileImportServiceProtocol {

    // MARK: - Properties

    private let fileManager: FileManager
    private let studyDataService: StudyDataService
    private let decoderFactory: () -> DicomDecoderProtocol
    private let logger: AnyLogger

    // MARK: - Initialization

    public init(
        fileManager: FileManager = .default,
        decoderFactory: @escaping () -> DicomDecoderProtocol
    ) {
        self.fileManager = fileManager
        self.decoderFactory = decoderFactory
        self.studyDataService = StudyDataService(
            fileManager: fileManager,
            decoderFactory: decoderFactory
        )
        self.logger = AnyLogger.make(subsystem: "com.dicomviewer", category: "FileImport")
        logger.info("📁 FileImportService initialized with dependency injection")
    }

    // MARK: - Legacy Singleton Support (deprecated)
    @available(*, deprecated, message: "Use dependency injection instead")
    public static let shared = FileImportService(decoderFactory: { DCMDecoder() })
    
    // MARK: - Public Methods
    
    func importFile(from url: URL, silent: Bool) async throws -> ImportResult {
        let success = await handleFileImport(url: url, silent: silent)
        return ImportResult(success: success, filePath: success ? url.path : nil, error: nil)
    }
    
    func extractZip(at url: URL, silent: Bool) async throws -> ExtractResult {
        // Implementation handled by handleFileImport for zip files
        let success = await handleFileImport(url: url, silent: silent)
        return ExtractResult(extractedCount: success ? 1 : 0, errors: [], paths: [])
    }
    
    func handleFileImport(url: URL, silent: Bool = false) async -> Bool {
        if !silent {
            await showProgress(text: "Importing: \(url.lastPathComponent)")
        }
        let success = await process(url: url)
        
        await hideProgress()
        if success {
            if !silent {
                await showSuccess(text: "Import complete")
            }
        } else {
            await handleImportError(
                error: DICOMError.invalidDICOMFormat(reason: "Could not import file: \(url.lastPathComponent)"),
                filename: url.lastPathComponent,
                silent: silent
            )
        }
        
        NotificationCenter.default.post(name: Notification.Name("DICOMFileImported"), object: nil)
        return success
    }
    
    // MARK: - Recursive Process Method
    
    private func process(url: URL) async -> Bool {
        let secured = url.startAccessingSecurityScopedResource()
        defer { if secured { url.stopAccessingSecurityScopedResource() } }

        do {
            let tempURL = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString + "_" + url.lastPathComponent)
            try fileManager.createDirectory(at: tempURL.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: nil)
            try fileManager.copyItem(at: url, to: tempURL)
            defer { try? fileManager.removeItem(at: tempURL) }
            
            if tempURL.pathExtension.lowercased() == "zip" {
                print("📦 ZIP found: \(tempURL.lastPathComponent). Extracting with robust method...")
                let tempExtractionDir = fileManager.temporaryDirectory.appendingPathComponent("zip_extract_\(UUID().uuidString)")
                defer { try? fileManager.removeItem(at: tempExtractionDir) }
                
                // --- CALL TO NEW EXTRACTOR ---
                let extractedPaths = try await ProperZipExtractor.extract(from: tempURL, to: tempExtractionDir)
                
                // --- RECURSIVE LOGIC ---
                print("📂 Processing \(extractedPaths.count) extracted files...")
                var importedCount = 0
                
                for (index, path) in extractedPaths.enumerated() {
                    print("📄 [\(index+1)/\(extractedPaths.count)] Processing: \(URL(fileURLWithPath: path).lastPathComponent)")
                    let fileProcessed = await process(url: URL(fileURLWithPath: path))
                    if fileProcessed {
                        importedCount += 1
                    }
                }
                
                print("📊 ZIP processing summary: \(importedCount) of \(extractedPaths.count) files imported")
                
                if importedCount > 0 {
                    print("✅ Successfully imported \(importedCount) DICOM files from ZIP")
                    // Send notification after processing ZIP contents
                    NotificationCenter.default.post(name: Notification.Name("DICOMFileImported"), object: nil)
                    return true
                } else {
                    print("⚠️ No DICOM files were imported from ZIP")
                    return false
                }
                
            } else {
                // If not a ZIP, try to move as a DICOM file
                print("🔍 Processing potential DICOM file: \(tempURL.lastPathComponent)")
                let fileSize = (try? fileManager.attributesOfItem(atPath: tempURL.path)[.size] as? Int64) ?? 0
                print("🔍 File size: \(fileSize) bytes")
                
                if let securePath = await moveToSecureLocation(from: tempURL.path) {
                    print("✅ DICOM file imported to: \(securePath)")
                    return true
                } else {
                    print("⚠️ File ignored (non-DICOM, duplicate or folder): \(tempURL.lastPathComponent)")
                    return false
                }
            }
        } catch {
            print("❌ Failed to process file \(url.lastPathComponent): \(error)")
            return false
        }
    }
    
    // MARK: - Recursive Import Processing
    
    /// Process import folder recursively until empty
    private func processImportFolderRecursively(folderURL: URL, silent: Bool = false) async -> (imported: Int, skipped: Int, errors: Int) {
        print("🔄 Starting recursive processing of folder: \(folderURL.path)")
        print("📊 Folder exists: \(fileManager.fileExists(atPath: folderURL.path))")
        
        var totalImported = 0
        var totalSkipped = 0
        var totalErrors = 0
        var hasChanges = true
        var iteration = 0
        
        // Keep processing until no more changes
        while hasChanges {
            iteration += 1
            print("🔁 Iteration \(iteration) - Processing folder: \(folderURL.lastPathComponent)")
            hasChanges = false
            
            do {
                let contents = try fileManager.contentsOfDirectory(at: folderURL, 
                                                                  includingPropertiesForKeys: [.isDirectoryKey],
                                                                  options: [.skipsHiddenFiles])
                
                print("📋 Found \(contents.count) items in folder")
                
                if contents.isEmpty {
                    print("✅ Import folder is empty, processing complete")
                    break
                }
                
                for (index, itemURL) in contents.enumerated() {
                    let isDirectory = (try? itemURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
                    
                    print("🔍 [\(index+1)/\(contents.count)] Processing: \(itemURL.lastPathComponent) - isDirectory: \(isDirectory)")
                    
                    if isDirectory {
                        // Process subdirectory recursively
                        print("📁 Entering subdirectory: \(itemURL.lastPathComponent) at path: \(itemURL.path)")
                        let subResult = await processImportFolderRecursively(folderURL: itemURL, silent: silent)
                        print("📁 Subdirectory results: imported=\(subResult.imported), skipped=\(subResult.skipped), errors=\(subResult.errors)")
                        totalImported += subResult.imported
                        totalSkipped += subResult.skipped
                        totalErrors += subResult.errors
                        
                        // Remove empty directory
                        if (try? fileManager.contentsOfDirectory(at: itemURL, includingPropertiesForKeys: nil))?.isEmpty ?? true {
                            try? fileManager.removeItem(at: itemURL)
                            print("🗑️ Removed empty directory: \(itemURL.lastPathComponent)")
                        }
                        hasChanges = true
                        
                    } else if itemURL.pathExtension.lowercased() == "zip" {
                        // Extract ZIP to a subfolder to avoid conflicts
                        print("📦 Processing nested ZIP: \(itemURL.lastPathComponent)")
                        
                        // Create a temporary folder for this ZIP's contents
                        let zipName = itemURL.deletingPathExtension().lastPathComponent
                        let extractFolder = folderURL.appendingPathComponent("extract_\(zipName)_\(UUID().uuidString.prefix(8))")
                        
                        do {
                            try fileManager.createDirectory(at: extractFolder, withIntermediateDirectories: true)
                            print("📁 Created extraction folder: \(extractFolder.lastPathComponent)")
                            
                            // Extract to the temporary folder and WAIT for completion
                            print("⏳ Starting extraction of nested ZIP...")
                            await extractZipToFolder(zipURL: itemURL, targetFolder: extractFolder, silent: silent)
                            print("✅ Extraction completed for: \(itemURL.lastPathComponent)")
                            
                            // Wait a bit to ensure all file writes are flushed
                            print("⏱️ Waiting for file system to settle...")
                            try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
                            
                            // Verify extraction completed by checking folder contents
                            let extractedContents = try fileManager.contentsOfDirectory(at: extractFolder, includingPropertiesForKeys: [.fileSizeKey])
                            print("📊 Extracted \(extractedContents.count) items to process")
                            
                            // Delete the ZIP after extraction
                            try? fileManager.removeItem(at: itemURL)
                            print("🗑️ Removed processed ZIP: \(itemURL.lastPathComponent)")
                            
                            // The recursive processing will handle the extracted contents
                            hasChanges = true
                        } catch {
                            print("❌ Failed to create extraction folder: \(error)")
                            totalErrors += 1
                        }
                        
                    } else {
                        // Try to process as DICOM (even without extension)
                        print("📄 Checking if file is DICOM: \(itemURL.lastPathComponent)")
                        
                        // Check file size to ensure it's not being written
                        let attrs = try? fileManager.attributesOfItem(atPath: itemURL.path)
                        let fileSize = attrs?[.size] as? Int64 ?? 0
                        
                        if fileSize == 0 {
                            print("⚠️ File has zero size, skipping for now: \(itemURL.lastPathComponent)")
                            // Don't delete it yet, it might still be extracting
                            continue
                        }
                        
                        // Double-check file size after a brief delay
                        try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
                        let attrs2 = try? fileManager.attributesOfItem(atPath: itemURL.path)
                        let fileSize2 = attrs2?[.size] as? Int64 ?? 0
                        
                        if fileSize != fileSize2 {
                            print("⚠️ File size is still changing (\(fileSize) → \(fileSize2)), skipping: \(itemURL.lastPathComponent)")
                            hasChanges = true // Try again in next iteration
                            continue
                        }
                        
                        print("📏 File size stable at \(fileSize) bytes")
                        
                        if extractDICOMUIDs(from: itemURL.path) != nil {
                            print("✓ File is DICOM, attempting to move to secure location...")
                            if await moveToSecureLocation(from: itemURL.path) != nil {
                                print("✅ Successfully imported DICOM file: \(itemURL.lastPathComponent)")
                                totalImported += 1
                            } else {
                                print("⚠️ Skipped duplicate: \(itemURL.lastPathComponent)")
                                totalSkipped += 1
                            }
                        } else {
                            // Not a DICOM file, remove it
                            print("❌ Not a DICOM file, removing: \(itemURL.lastPathComponent)")
                            try? fileManager.removeItem(at: itemURL)
                            print("🗑️ Removed non-DICOM file: \(itemURL.lastPathComponent)")
                            totalErrors += 1
                        }
                        hasChanges = true
                    }
                }
                
            } catch {
                print("❌ Error processing folder: \(error)")
                totalErrors += 1
            }
        }
        
        print("📊 Recursive processing complete - Imported: \(totalImported), Skipped: \(totalSkipped), Errors: \(totalErrors)")
        return (totalImported, totalSkipped, totalErrors)
    }
    
    /// Extract ZIP to a specific folder with recursive nested ZIP support
    private func extractZipToFolder(zipURL: URL, targetFolder: URL, silent: Bool) async {
        print("📦 Extracting ZIP to folder: \(zipURL.lastPathComponent) → \(targetFolder.path)")
        print("📦 ZIP file exists: \(fileManager.fileExists(atPath: zipURL.path))")
        print("📦 Target folder exists: \(fileManager.fileExists(atPath: targetFolder.path))")
        
        // Use ProperZipExtractor for robust extraction
        print("📦 Using ProperZipExtractor for ZIP extraction...")
        
        do {
            // Use robust extraction with ZipFoundation
            let extractedPaths = try await ProperZipExtractor.extract(
                from: zipURL, 
                to: targetFolder
            )
            
            print("✅ Extracted \(extractedPaths.count) files from ZIP")
            
            // Progress notification handled by calling method
            
        } catch {
            print("❌ Failed to extract ZIP: \(error)")
            // No fallback needed - ZipFoundation is robust
        }
        
        // Add extra safety delay after extraction
        print("⏱️ Waiting for file system to flush...")
        try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
        
        // List what's actually in the target folder now
        print("\n📁 Verifying target folder contents...")
        
        var allContents: [URL] = []
        do {
            allContents = try FileManager.default.contentsOfDirectory(
                at: targetFolder,
                includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey],
                options: [.skipsHiddenFiles]
            )
        } catch {
            print("⚠️ Error listing directory: \(error)")
        }
        
        print("📊 Total items in target: \(allContents.count)")
        
        var fileCount = 0
        var dirCount = 0
        var totalSize: Int64 = 0
        
        for item in allContents.prefix(20) {
            let resources = try? item.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey])
            let isDir = resources?.isDirectory ?? false
            let fileSize = resources?.fileSize ?? 0
            
            if isDir {
                dirCount += 1
                print("  📁 DIR: \(item.lastPathComponent)")
            } else {
                fileCount += 1
                totalSize += Int64(fileSize)
                print("  📄 FILE: \(item.lastPathComponent) (\(fileSize) bytes)")
            }
        }
        
        if allContents.count > 20 {
            print("  ... and \(allContents.count - 20) more items")
        }
        
        print("\n📊 Summary: \(fileCount) files (\(totalSize) bytes), \(dirCount) directories")
        print("📦 ===== END EXTRACTION =====\n")
        
        print("📦 extractZipToFolder completed for \(zipURL.lastPathComponent)")
    }
    
    // Helper method to list directory contents recursively
    private func listDirectoryRecursively(at url: URL) throws -> [URL] {
        var allItems: [URL] = []
        
        if let enumerator = fileManager.enumerator(at: url, 
                                                   includingPropertiesForKeys: [.isDirectoryKey],
                                                   options: [.skipsHiddenFiles]) {
            for case let itemURL as URL in enumerator {
                allItems.append(itemURL)
            }
        }
        
        return allItems
    }
    
    // MARK: - Private Methods
    
    private func processFileImport(url: URL, isZip: Bool, silent: Bool) async {
        // Use secure studies directory structure
        guard let _ = getStudiesBaseURL() else {
            print("❌ Could not access secure studies directory for import")
            return
        }
        
        // Start accessing security-scoped resource
        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed {
                url.stopAccessingSecurityScopedResource()
            }
        }
        
        if !silent {
            await showProgress(text: "Importing: \(url.lastPathComponent)")
        }
        
        do {
            // Copy to temp first
            let tempDir = fileManager.temporaryDirectory
            let tempURL = tempDir.appendingPathComponent(url.lastPathComponent)
            
            if fileManager.fileExists(atPath: tempURL.path) {
                try fileManager.removeItem(at: tempURL)
            }
            
            // Check file attributes
            let fileAttributes = try fileManager.attributesOfItem(atPath: url.path)
            let fileSize = fileAttributes[.size] as? Int64 ?? 0
            print("📊 File size: \(fileSize) bytes")
            
            try fileManager.copyItem(at: url, to: tempURL)
            print("✅ Copied to temp: \(tempURL.path)")
            
            if isZip {
                // Extract ZIP
                await extractZipFileAsync(at: tempURL, silent: silent)
            } else {
                // Move DICOM file to secure location
                if let securePath = await moveToSecureLocation(from: tempURL.path) {
                    print("✅ File imported to secure structure: \(securePath)")
                    
                    if !silent {
                        await hideProgress()
                        await showSuccess(text: "Import complete")
                    }
                } else {
                    print("❌ Failed to move file to secure structure: \(tempURL.path)")
                }
            }
            
            // Send notification after processing
            await notifyImportComplete(filename: url.lastPathComponent, silent: silent)
            
        } catch {
            print("❌ Error importing file \(url.lastPathComponent): \(error.localizedDescription)")
            await handleImportError(error: error, filename: url.lastPathComponent, silent: silent)
        }
    }
    
    private func getStudiesBaseURL() -> URL? {
        guard let appSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            print("❌ Could not access Application Support directory")
            return nil
        }
        let studiesURL = appSupportURL.appendingPathComponent("Studies")
        
        // Create directory if it doesn't exist
        if !fileManager.fileExists(atPath: studiesURL.path) {
            do {
                try fileManager.createDirectory(at: studiesURL, withIntermediateDirectories: true, attributes: nil)
                print("✅ Created secure studies directory: \(studiesURL.path)")
            } catch {
                print("❌ Error creating Studies directory: \(error)")
                return nil
            }
        }
        return studiesURL
    }
    
    private func createDICOMFilePath(studyUID: String, seriesUID: String, sopUID: String) -> URL? {
        guard let studiesURL = getStudiesBaseURL() else { return nil }
        
        // Structure: Studies/{StudyInstanceUID}/{SeriesInstanceUID}/{SOPInstanceUID}.dcm
        let studyDir = studiesURL.appendingPathComponent(studyUID)
        let seriesDir = studyDir.appendingPathComponent(seriesUID)
        let finalPath = seriesDir.appendingPathComponent("\(sopUID).dcm")
        
        // Create directories if they don't exist
        do {
            try fileManager.createDirectory(at: seriesDir, withIntermediateDirectories: true, attributes: nil)
            return finalPath
        } catch {
            print("❌ Error creating directory structure: \(error)")
            return nil
        }
    }
    
    private func extractDICOMUIDs(from filePath: String) -> (studyUID: String, seriesUID: String, sopUID: String)? {
        print("\n🔍 [UID] Extracting UIDs from: \(URL(fileURLWithPath: filePath).lastPathComponent)")
        print("🔍 [UID] Full path: \(filePath)")
        print("🔍 [UID] File exists: \(fileManager.fileExists(atPath: filePath))")
        
        if let attributes = try? fileManager.attributesOfItem(atPath: filePath) {
            let size = attributes[.size] as? Int64 ?? 0
            print("🔍 [UID] File size: \(size) bytes")
            
            // Check if it's actually a file not a directory
            let isDir = attributes[.type] as? FileAttributeType == .typeDirectory
            if isDir {
                print("❌ [UID] This is a directory, not a file!")
                return nil
            }
        } else {
            print("❌ [UID] Could not get file attributes")
            return nil
        }
        
        print("🔍 [UID] Creating DCMDecoder...")
        let decoder = DCMDecoder()
        
        print("🔍 [UID] Setting DICOM filename...")
        decoder.setDicomFilename(filePath)
        
        print("🔍 [UID] Checking if DICOM read was successful...")
        guard decoder.dicomFileReadSuccess else {
            print("❌ [UID] DICOM file read failed")
            print("❌ [UID] Not a valid DICOM file: \(URL(fileURLWithPath: filePath).lastPathComponent)")
            return nil
        }
        print("✅ [UID] DICOM file read successful")
        
        // Use DICOM tag constants
        let studyUID = decoder.info(for: DicomTag.studyInstanceUID.rawValue)
        let seriesUID = decoder.info(for: DicomTag.seriesInstanceUID.rawValue)
        let sopUID = decoder.info(for: DicomTag.sopInstanceUID.rawValue)
        
        if studyUID.isEmpty || seriesUID.isEmpty || sopUID.isEmpty {
            print("❌ Could not extract UIDs from: \(filePath)")
            return nil
        }
        
        print("✅ Successfully extracted UIDs")
        return (studyUID: studyUID, seriesUID: seriesUID, sopUID: sopUID)
    }
    
    private func moveToSecureLocation(from tempPath: String) async -> String? {
        print("📦 Starting moveToSecureLocation for: \(tempPath)")
        
        guard let uids = extractDICOMUIDs(from: tempPath) else {
            print("❌ Failed to extract UIDs from: \(tempPath)")
            return nil
        }
        
        guard let destinationURL = createDICOMFilePath(studyUID: uids.studyUID,
                                                     seriesUID: uids.seriesUID,
                                                     sopUID: uids.sopUID) else {
            print("❌ Failed to create destination path")
            return nil
        }
        
        print("📦 Destination URL: \(destinationURL.path)")
        
        do {
            // Check if file already exists - if yes, it's a duplicate, skip it
            if fileManager.fileExists(atPath: destinationURL.path) {
                // Check if files are identical by comparing size
                let existingAttributes = try fileManager.attributesOfItem(atPath: destinationURL.path)
                let newAttributes = try fileManager.attributesOfItem(atPath: tempPath)
                
                let existingSize = existingAttributes[.size] as? Int64 ?? 0
                let newSize = newAttributes[.size] as? Int64 ?? 0
                
                if existingSize == newSize {
                    print("⚠️ Identical file already exists, skipping: \(destinationURL.lastPathComponent)")
                    // Remove temp file since we're not using it
                    try fileManager.removeItem(atPath: tempPath)
                    return nil // Return nil to indicate duplicate was skipped
                } else {
                    print("⚠️ Different file with same UIDs exists. Size: existing=\(existingSize), new=\(newSize)")
                    print("📝 Keeping existing file, discarding new one")
                    // Remove temp file, keep existing
                    try fileManager.removeItem(atPath: tempPath)
                    return nil // Return nil to indicate duplicate was skipped
                }
            }
            
            // Move file to secure location (no file exists yet)
            try fileManager.moveItem(atPath: tempPath, toPath: destinationURL.path)
            print("✅ File moved to secure structure: \(destinationURL.path)")
            
            // Update series cache for this file
            await updateSeriesCacheForFile(studyUID: uids.studyUID, 
                                          seriesUID: uids.seriesUID, 
                                          filePath: destinationURL.path)
            
            return destinationURL.path
        } catch {
            print("❌ Error moving file to secure structure: \(error)")
            return nil
        }
    }
    
    /// Update series cache when adding a new file
    private func updateSeriesCacheForFile(studyUID: String, seriesUID: String, filePath: String) async {
        print("💾 Updating series cache for new file in study \(studyUID), series \(seriesUID)")
        
        // Get cache service
        let cacheService: StudyMetadataCacheService
        do {
            cacheService = try StudyMetadataCacheService()
        } catch {
            print("❌ Could not create cache service: \(error)")
            return
        }
        
        // Load existing series cache for this study
        do {
            var existingSeries = try await cacheService.loadSeriesMetadata(for: studyUID)
            
            // Find or create series metadata
            if let seriesIndex = existingSeries.firstIndex(where: { $0.seriesInstanceUID == seriesUID }) {
                // Series exists, update file count and paths
                let currentSeries = existingSeries[seriesIndex]
                
                // Convert to relative path for storage
                let relativePath: String
                if let appSupportURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
                    let studiesURL = appSupportURL.appendingPathComponent("Studies")
                    relativePath = filePath.replacingOccurrences(of: studiesURL.path + "/", with: "")
                } else {
                    relativePath = "\(studyUID)/\(seriesUID)/\(URL(fileURLWithPath: filePath).lastPathComponent)"
                }
                
                // Add file path if not already present
                if !currentSeries.filePaths.contains(relativePath) {
                    // Create new series metadata with updated paths
                    var updatedPaths = currentSeries.filePaths
                    updatedPaths.append(relativePath)
                    
                    let updatedSeries = CachedSeriesMetadata(
                        seriesInstanceUID: currentSeries.seriesInstanceUID,
                        studyInstanceUID: currentSeries.studyInstanceUID,
                        seriesNumber: currentSeries.seriesNumber,
                        seriesDescription: currentSeries.seriesDescription,
                        modality: currentSeries.modality,
                        imageCount: updatedPaths.count,
                        filePaths: updatedPaths,
                        thumbnailImagePath: currentSeries.thumbnailImagePath ?? relativePath
                    )
                    
                    existingSeries[seriesIndex] = updatedSeries
                    
                    // Save updated cache
                    try await cacheService.saveSeriesMetadata(existingSeries, for: studyUID)
                    print("✅ Updated series cache - now \(updatedSeries.imageCount) images in series")
                }
            } else {
                // New series, extract metadata and create entry
                if let metadata = extractMinimalSeriesMetadata(from: filePath) {
                    let relativePath: String
                    if let appSupportURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
                        let studiesURL = appSupportURL.appendingPathComponent("Studies")
                        relativePath = filePath.replacingOccurrences(of: studiesURL.path + "/", with: "")
                    } else {
                        relativePath = "\(studyUID)/\(seriesUID)/\(URL(fileURLWithPath: filePath).lastPathComponent)"
                    }
                    
                    let newSeries = CachedSeriesMetadata(
                        seriesInstanceUID: seriesUID,
                        studyInstanceUID: studyUID,
                        seriesNumber: metadata.seriesNumber,
                        seriesDescription: metadata.seriesDescription,
                        modality: metadata.modality,
                        imageCount: 1,
                        filePaths: [relativePath],
                        thumbnailImagePath: relativePath
                    )
                    
                    existingSeries.append(newSeries)
                    try await cacheService.saveSeriesMetadata(existingSeries, for: studyUID)
                    print("✅ Created new series cache entry")
                }
            }
        } catch {
            print("⚠️ Could not update series cache: \(error)")
            // Not critical - cache will be rebuilt on next access
        }
    }
    
    private func extractZipFileAsync(at url: URL, silent: Bool) async {
        print("\n========== START ZIP EXTRACTION ==========")
        print("📦 Starting recursive ZIP extraction for: \(url.lastPathComponent)")
        print("📦 ZIP URL: \(url.path)")
        print("📦 ZIP exists: \(fileManager.fileExists(atPath: url.path))")
        if let attrs = try? fileManager.attributesOfItem(atPath: url.path) {
            print("📦 ZIP size: \(attrs[.size] as? Int64 ?? 0) bytes")
        }
        
        let tempExtractionDir = fileManager.temporaryDirectory.appendingPathComponent("zip_extract_\(UUID().uuidString)")
        print("📦 Temp extraction directory: \(tempExtractionDir.path)")
        
        do {
            print("📦 [1] Creating temp directory...")
            try fileManager.createDirectory(at: tempExtractionDir, withIntermediateDirectories: true, attributes: nil)
            print("✅ [1] Created temp directory successfully")
            
            // First, extract the ZIP to temp folder
            print("\n📦 [2] STARTING ZIP EXTRACTION...")
            print("📦 [2] Calling extractZipToFolder...")
            await extractZipToFolder(zipURL: url, targetFolder: tempExtractionDir, silent: silent)
            print("📦 [2] extractZipToFolder returned")
            
            // List what was extracted
            print("\n📦 [3] LISTING EXTRACTED CONTENTS...")
            let extractedContents = try fileManager.contentsOfDirectory(at: tempExtractionDir, includingPropertiesForKeys: [.isDirectoryKey])
            print("📋 [3] Found \(extractedContents.count) items in temp folder:")
            for (idx, item) in extractedContents.enumerated() {
                let isDir = (try? item.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
                let attrs = try? fileManager.attributesOfItem(atPath: item.path)
                let size = attrs?[.size] as? Int64 ?? 0
                print("  [\(idx+1)] \(item.lastPathComponent) \(isDir ? "📁 DIR" : "📄 FILE") (\(size) bytes)")
            }
            
            // Then process the folder recursively (handles nested ZIPs, folders, etc.)
            print("\n📦 [4] STARTING RECURSIVE PROCESSING...")
            let result = await processImportFolderRecursively(folderURL: tempExtractionDir, silent: silent)
            print("📦 [4] Recursive processing returned: imported=\(result.imported), skipped=\(result.skipped), errors=\(result.errors)")
            
            print("📊 ZIP import complete - Imported: \(result.imported), Skipped: \(result.skipped), Errors: \(result.errors)")
            
            // Clean up temp directory
            try? fileManager.removeItem(at: tempExtractionDir)
            
            // Cache series metadata after import
            // Note: This is now handled within moveToSecureLocation for each file
            
            // Hide progress and show results
            await hideProgress()
            if !silent {
                if result.imported > 0 {
                    await showSuccess(text: "Imported \(result.imported) DICOM files (\(result.skipped) duplicates skipped)")
                } else if result.skipped > 0 {
                    await showSuccess(text: "All \(result.skipped) files were duplicates")
                } else {
                    await showSuccess(text: "No valid DICOM files found")
                }
            }
            
            // Notify StudyManager to reload
            print("\n📦 [8] NOTIFYING STUDY MANAGER...")
            NotificationCenter.default.post(
                name: Notification.Name("DICOMFileImported"),
                object: nil,
                userInfo: ["fileCount": result.imported]
            )
            print("========== END ZIP EXTRACTION ==========\n")
            
        } catch {
            print("\n❌ ERROR during ZIP extraction: \(error)")
            print("❌ Error type: \(type(of: error))")
            print("❌ Error localized: \(error.localizedDescription)")
            print("========== END ZIP EXTRACTION (ERROR) ==========\n")
        }
    }
    
    // MARK: - Series Caching
    
    private func cacheSeriesMetadataForImport(_ seriesMetadataByStudy: [String: [String: [String]]]) async {
        print("📊 Caching series for \(seriesMetadataByStudy.count) studies...")
        
        // Get cache service directly (it's initialized in StudyManager)
        let cacheService: StudyMetadataCacheService
        do {
            cacheService = try StudyMetadataCacheService()
        } catch {
            print("❌ Could not create cache service for series caching: \(error)")
            return
        }
        
        // Process each study
        for (studyUID, seriesByUID) in seriesMetadataByStudy {
            var seriesMetadataList: [CachedSeriesMetadata] = []
            
            for (seriesUID, filePaths) in seriesByUID {
                // Get metadata from first file for series info
                if let firstFilePath = filePaths.first,
                   let appSupportURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
                    let studiesURL = appSupportURL.appendingPathComponent("Studies")
                    let fullPath = studiesURL.appendingPathComponent(firstFilePath).path
                    
                    // Extract minimal metadata for series
                    if let metadata = extractMinimalSeriesMetadata(from: fullPath) {
                        let seriesMetadata = CachedSeriesMetadata(
                            seriesInstanceUID: seriesUID,
                            studyInstanceUID: studyUID,
                            seriesNumber: metadata.seriesNumber,
                            seriesDescription: metadata.seriesDescription,
                            modality: metadata.modality,
                            imageCount: filePaths.count,
                            filePaths: filePaths, // Already relative paths
                            thumbnailImagePath: filePaths.count > 0 ? filePaths[filePaths.count / 2] : nil
                        )
                        seriesMetadataList.append(seriesMetadata)
                    }
                }
            }
            
            // Save series cache for this study
            if !seriesMetadataList.isEmpty {
                do {
                    try await cacheService.saveSeriesMetadata(seriesMetadataList, for: studyUID)
                    print("✅ Cached \(seriesMetadataList.count) series for study \(studyUID)")
                } catch {
                    print("❌ Failed to cache series for study \(studyUID): \(error)")
                }
            }
        }
    }
    
    private func extractMinimalSeriesMetadata(from filePath: String) -> (seriesNumber: String?, seriesDescription: String?, modality: String)? {
        let decoder = DCMDecoder()
        decoder.setDicomFilename(filePath)
        
        guard decoder.dicomFileReadSuccess else {
            return nil
        }
        
        let seriesNumber = decoder.info(for: DicomTag.seriesNumber.rawValue).isEmpty ? nil : decoder.info(for: DicomTag.seriesNumber.rawValue)
        let seriesDescription = decoder.info(for: DicomTag.seriesDescription.rawValue).isEmpty ? nil : decoder.info(for: DicomTag.seriesDescription.rawValue)
        let modality = decoder.info(for: DicomTag.modality.rawValue).isEmpty ? "OT" : decoder.info(for: DicomTag.modality.rawValue)
        
        return (seriesNumber: seriesNumber, seriesDescription: seriesDescription, modality: modality)
    }
    
    // MARK: - UI Helper Methods
    
    private func findMainViewController() -> UIViewController? {
        var topViewController: UIViewController?
        
        if #available(iOS 13.0, *) {
            let validActivationStates: [UIScene.ActivationState] = [.foregroundActive, .foregroundInactive]
            
            if let windowScene = UIApplication.shared.connectedScenes
                .first(where: { validActivationStates.contains($0.activationState) }) as? UIWindowScene,
               let sceneWindow = windowScene.windows.first(where: { $0.isKeyWindow }) {
                topViewController = sceneWindow.rootViewController
            }
        }
        
        // Fallback to app delegate window
        if topViewController == nil,
           let appDelegate = UIApplication.shared.delegate as? SwiftAppDelegate {
            topViewController = appDelegate.window?.rootViewController
        }
        
        // Navigate through tab bar controller to find the main view controller
        if let tabBarController = topViewController as? UITabBarController,
           let navController = tabBarController.viewControllers?.first as? UINavigationController,
           let mainVC = navController.viewControllers.first {
            return mainVC
        }
        
        // Navigate to the actual top-most presented view controller
        while let presentedVC = topViewController?.presentedViewController {
            topViewController = presentedVC
        }
        
        return topViewController
    }
    
    private func showProgress(text: String) async {
        if let mainVC = findMainViewController() {
            _ = NativeProgressHUD.show(to: mainVC.view, text: text, animated: true)
        }
    }
    
    private func hideProgress() async {
        if let mainVC = findMainViewController() {
            NativeProgressHUD.hide(from: mainVC.view, animated: true)
        }
    }
    
    private func showSuccess(text: String) async {
        if let mainVC = findMainViewController() {
            NativeProgressHUD.showSuccess(to: mainVC.view, text: text)
        }
    }
    
    private func notifyImportComplete(filename: String, silent: Bool) async {
        if let mainVC = findMainViewController() {
            NativeProgressHUD.hide(from: mainVC.view, animated: true)
        }
        
        NotificationCenter.default.post(
            name: Notification.Name("DICOMFileImported"),
            object: nil,
            userInfo: ["filename": filename]
        )
        
        if !silent {
            await showSuccess(text: "Successfully imported \(filename)")
        }
    }
    
    private func handleImportError(error: Error, filename: String, silent: Bool) async {
        if let mainVC = findMainViewController() {
            NativeProgressHUD.hide(from: mainVC.view, animated: true)
        }
        
        if !silent {
            if let mainVC = findMainViewController() {
                let alert = UIAlertController(
                    title: "Import Failed",
                    message: "Failed to import \(filename): \(error.localizedDescription)",
                    preferredStyle: .alert
                )
                alert.addAction(UIAlertAction(title: "OK", style: .default))
                mainVC.present(alert, animated: true)
            }
        }
    }
}

// MARK: - Bridge Class
// Note: SwiftZipExtractorWrapper is already defined in SwiftZipExtractor.swift