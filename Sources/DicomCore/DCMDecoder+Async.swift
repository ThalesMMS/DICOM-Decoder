//
//  DCMDecoder+Async.swift
//
//  Async/await extensions for DCMDecoder providing modern concurrency
//  support for loading DICOM files and retrieving pixel data.
//
//  All async methods run on detached tasks with appropriate priority
//  levels to avoid blocking the main thread while preserving thread
//  safety guarantees of the underlying synchronous methods.
//

import Foundation

// MARK: - Async/Await Extensions

extension DCMDecoder {

    /// Loads and decodes a DICOM file asynchronously
    /// - Parameter filename: Path to the DICOM file
    /// - Returns: True if the file was successfully loaded and decoded
    @available(macOS 10.15, iOS 13.0, *)
    public func loadDICOMFileAsync(_ filename: String) async -> Bool {
        return await withCheckedContinuation { continuation in
            Task.detached(priority: .userInitiated) {
                self.setDicomFilename(filename)
                continuation.resume(returning: self.dicomFileReadSuccess)
            }
        }
    }

    /// Retrieves 16-bit pixels asynchronously
    /// - Returns: Array of 16-bit pixel values or nil
    @available(macOS 10.15, iOS 13.0, *)
    public func getPixels16Async() async -> [UInt16]? {
        return await withCheckedContinuation { continuation in
            Task.detached(priority: .userInitiated) {
                continuation.resume(returning: self.getPixels16())
            }
        }
    }

    /// Retrieves 8-bit pixels asynchronously
    /// - Returns: Array of 8-bit pixel values or nil
    @available(macOS 10.15, iOS 13.0, *)
    public func getPixels8Async() async -> [UInt8]? {
        return await withCheckedContinuation { continuation in
            Task.detached(priority: .userInitiated) {
                continuation.resume(returning: self.getPixels8())
            }
        }
    }

    /// Retrieves 24-bit RGB pixels asynchronously
    /// - Returns: Array of 24-bit pixel values or nil
    @available(macOS 10.15, iOS 13.0, *)
    public func getPixels24Async() async -> [UInt8]? {
        return await withCheckedContinuation { continuation in
            Task.detached(priority: .userInitiated) {
                continuation.resume(returning: self.getPixels24())
            }
        }
    }

    /// Retrieves downsampled thumbnail pixels asynchronously
    /// - Parameter maxDimension: Maximum dimension for the thumbnail
    /// - Returns: Tuple with downsampled pixels and dimensions, or nil
    @available(macOS 10.15, iOS 13.0, *)
    public func getDownsampledPixels16Async(maxDimension: Int = 150) async -> (pixels: [UInt16], width: Int, height: Int)? {
        return await withCheckedContinuation { continuation in
            Task.detached(priority: .utility) {
                continuation.resume(returning: self.getDownsampledPixels16(maxDimension: maxDimension))
            }
        }
    }
}
