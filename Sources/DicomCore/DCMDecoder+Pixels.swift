import Foundation

extension DCMDecoder {
    /// Retrieve the decoded 8-bit pixel buffer for the DICOM image.
    /// Thread-safe; triggers lazy pixel decoding on first call.
    /// - Returns: The decoded 8-bit pixel buffer, or `nil` if pixel data could not be loaded.
    public func getPixels8() -> [UInt8]? {
        return synchronized {
            let startTime = CFAbsoluteTimeGetCurrent()
            guard ensurePixelsLoadedUnsafe() else {
                return nil
            }
            let elapsed = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
            if elapsed > 1 { debugPerfLog("[PERF] getPixels8: \(String(format: "%.2f", elapsed))ms") }
            return pixels8
        }
    }

    /// Returns the decoder's 16-bit pixel buffer, loading and decoding pixel data on first access if necessary.
    /// Thread-safe; triggers lazy pixel decoding on first call.
    /// - Returns: The 16-bit pixel samples as `[UInt16]` if available, `nil` if pixels could not be loaded.
    public func getPixels16() -> [UInt16]? {
        return synchronized {
            let startTime = CFAbsoluteTimeGetCurrent()
            guard ensurePixelsLoadedUnsafe() else {
                return nil
            }
            let elapsed = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
            if elapsed > 1 { debugPerfLog("[PERF] getPixels16: \(String(format: "%.2f", elapsed))ms") }
            return pixels16
        }
    }

    /// Returns the decoded 24-bit interleaved RGB pixel buffer, loading pixels on first access if needed.
    /// Thread-safe; triggers lazy pixel decoding on first call.
    /// - Returns: The 24-bit interleaved pixel buffer (RGB) as `[UInt8]` if available, or `nil` if pixel data could not be loaded.
    public func getPixels24() -> [UInt8]? {
        return synchronized {
            let startTime = CFAbsoluteTimeGetCurrent()
            guard ensurePixelsLoadedUnsafe() else {
                return nil
            }
            let elapsed = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
            if elapsed > 1 { debugPerfLog("[PERF] getPixels24: \(String(format: "%.2f", elapsed))ms") }
            return pixels24
        }
    }

    /// Reads uncompressed pixel data from the current DICOM byte buffer and updates the decoder's pixel caches.
    ///
    /// Clears existing pixel buffers and replaces them with results from `DCMPixelReader.readPixels(...)`, and updates `signedImage`.
    /// - Important: Must be called from within a synchronized block.
    private func readPixelsUnsafe() {
        // Clear any previously stored buffers
        pixels8 = nil
        pixels16 = nil
        pixels24 = nil

        // Use DCMPixelReader to read pixel data
        let result = DCMPixelReader.readPixels(
            data: dicomData,
            width: width,
            height: height,
            bitDepth: bitDepth,
            samplesPerPixel: samplesPerPixel,
            offset: offset,
            pixelRepresentation: pixelRepresentation,
            littleEndian: littleEndian,
            photometricInterpretation: photometricInterpretation,
            logger: logger
        )

        // Store the results
        pixels8 = result.pixels8
        pixels16 = result.pixels16
        pixels24 = result.pixels24
        signedImage = result.signedImage
    }

    /// Ensures the decoder's pixel buffers are loaded, performing decoding if necessary.
    ///
    /// Must be called from within a synchronized block. Triggers the appropriate decode path
    /// for compressed or uncompressed images and marks pixels as loaded.
    /// - Returns: `true` if the DICOM file was read successfully and pixel buffers are available (or already loaded), `false` otherwise.
    @inline(__always)
    private func ensurePixelsLoadedUnsafe() -> Bool {
        guard dicomFileReadSuccess else {
            return false
        }

        if !pixelsNotLoaded {
            return true
        }

        if compressedImage {
            decodeCompressedPixelDataUnsafe()
        } else {
            readPixelsUnsafe()
        }

        pixelsNotLoaded = false
        return dicomFileReadSuccess
    }

    /// Decodes compressed pixel data and updates the decoder's image state and cached pixel buffers.
    ///
    /// On success, updates `width`, `height`, `bitDepth`, `samplesPerPixel`, `signedImage` and stores pixel buffers.
    /// On failure, sets `dicomFileReadSuccess = false`.
    /// - Note: Must be called from within a synchronized block.
    private func decodeCompressedPixelDataUnsafe() {
        // Use DCMPixelReader to decode compressed pixel data
        guard let result = DCMPixelReader.decodeCompressedPixelData(
            data: dicomData,
            offset: offset,
            pixelRepresentation: pixelRepresentationTagValue,
            logger: logger
        ) else {
            dicomFileReadSuccess = false
            return
        }

        // Update decoder state with decoded image properties
        width = result.width
        height = result.height
        bitDepth = result.bitDepth
        samplesPerPixel = result.samplesPerPixel
        signedImage = result.signedImage

        // Store pixel buffers
        pixels8 = result.pixels8
        pixels16 = result.pixels16
        pixels24 = result.pixels24
    }
}