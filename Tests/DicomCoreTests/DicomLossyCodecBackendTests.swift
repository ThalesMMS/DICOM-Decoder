import CoreGraphics
import ImageIO
import XCTest
import DicomTestSupport
@testable import DicomCore

final class DicomLossyCodecBackendTests: XCTestCase {
    func testJPEGBaseline8BitUsesExplicitImageIOBackend() throws {
        let image = try makeGrayscaleImage8(width: 2, height: 2, pixels: [48, 96, 144, 192])
        let encoded = try encodeImage(image, type: "public.jpeg" as CFString)

        let result = try XCTUnwrap(DCMPixelReader.decodeCompressedFrameData(
            data: encoded,
            transferSyntax: .jpegBaseline,
            bitDepth: 8,
            samplesPerPixel: 1,
            pixelRepresentation: 0
        ))

        XCTAssertNotNil(result.pixels8)
        XCTAssertNil(result.pixels16)
        XCTAssertEqual(result.width, 2)
        XCTAssertEqual(result.height, 2)
        XCTAssertEqual(result.bitDepth, 8)
        XCTAssertEqual(result.samplesPerPixel, 1)
    }

    func testJPEG2000Lossless16BitGrayscalePreservesPrecision() throws {
        try DicomTestRuntimePreflight.require(.openJPEG)

        let pixels: [UInt16] = [0, 1024, 4096, 65535]
        let encoded = try makeOpenJPEGLosslessCodestream16(width: 2, height: 2, pixels: pixels)

        let result = try XCTUnwrap(DCMPixelReader.decodeCompressedFrameData(
            data: encoded,
            transferSyntax: .jpeg2000Lossless,
            bitDepth: 16,
            samplesPerPixel: 1,
            pixelRepresentation: 0
        ))

        XCTAssertEqual(result.pixels16, pixels)
        XCTAssertNil(result.pixels8)
        XCTAssertEqual(result.bitDepth, 16)
        XCTAssertEqual(result.samplesPerPixel, 1)
    }

    func testJPEG2000Lossy8BitUsesExplicitImageIOBackend() throws {
        let image = try makeGrayscaleImage8(width: 2, height: 2, pixels: [12, 64, 128, 240])
        let encoded = try encodeImage(
            image,
            type: "public.jpeg-2000" as CFString,
            properties: [kCGImageDestinationLossyCompressionQuality as String: 0.4] as CFDictionary
        )

        let result = try XCTUnwrap(DCMPixelReader.decodeCompressedFrameData(
            data: encoded,
            transferSyntax: .jpeg2000,
            bitDepth: 8,
            samplesPerPixel: 1,
            pixelRepresentation: 0
        ))

        XCTAssertNotNil(result.pixels8)
        XCTAssertNil(result.pixels16)
        XCTAssertEqual(result.width, 2)
        XCTAssertEqual(result.height, 2)
    }

    func testJPEGExtended12BitReturnsDiagnosticWithoutPrecisionLoss() {
        let logger = MockLogger()
        let result = DCMPixelReader.decodeCompressedFrameData(
            data: Data([0xFF, 0xD8, 0xFF, 0xC1, 0x00, 0x0B, 0x0C, 0x00, 0x01, 0x00, 0x01, 0x01, 0x01, 0x11, 0x00]),
            transferSyntax: .jpegExtended,
            bitDepth: 12,
            samplesPerPixel: 1,
            pixelRepresentation: 0,
            logger: logger
        )

        XCTAssertNil(result)
        XCTAssertTrue(logger.contains(level: .warning, text: "JPEG Extended 12-bit output"))
        XCTAssertTrue(logger.contains(level: .warning, text: "refusing ImageIO fallback"))
    }

    func testHTJ2KReturnsDiagnosticWithoutJPEG2000Fallback() {
        let logger = MockLogger()
        let result = DCMPixelReader.decodeCompressedFrameData(
            data: Data([0xFF, 0x4F, 0xFF, 0x51]),
            transferSyntax: .htj2kLossless,
            bitDepth: 16,
            samplesPerPixel: 1,
            pixelRepresentation: 0,
            logger: logger
        )

        XCTAssertNil(result)
        XCTAssertTrue(logger.contains(level: .warning, text: "requires an HTJ2K backend"))
        XCTAssertTrue(logger.contains(level: .warning, text: "ImageIO JPEG 2000 fallback is not used"))
    }

    func testBackendResolverDocumentsExplicitDecisions() {
        XCTAssertEqual(
            DicomCompressedPixelBackendResolver.resolve(
                transferSyntax: .jpegBaseline,
                requestedBitDepth: 8,
                samplesPerPixel: 1
            ).backend,
            .imageIOJPEGBaseline
        )
        XCTAssertEqual(
            DicomCompressedPixelBackendResolver.resolve(
                transferSyntax: .jpeg2000Lossless,
                requestedBitDepth: 16,
                samplesPerPixel: 1
            ).backend,
            DicomJPEG2000Codec.isAvailable ? .openJPEG2000 : .unsupported
        )
        XCTAssertEqual(
            DicomCompressedPixelBackendResolver.resolve(
                transferSyntax: .jpegExtended,
                requestedBitDepth: 12,
                samplesPerPixel: 1
            ).backend,
            .unsupported
        )
        XCTAssertEqual(
            DicomCompressedPixelBackendResolver.resolve(
                transferSyntax: .htj2k,
                requestedBitDepth: 16,
                samplesPerPixel: 1
            ).backend,
            .unsupported
        )
        XCTAssertEqual(
            DicomCompressedPixelBackendResolver.resolve(
                transferSyntax: .jpeg2000Part2MulticomponentLossless,
                requestedBitDepth: 16,
                samplesPerPixel: 1
            ).backend,
            .unsupported
        )
    }

    private func makeGrayscaleImage8(width: Int, height: Int, pixels: [UInt8]) throws -> CGImage {
        XCTAssertEqual(pixels.count, width * height)
        let provider = try XCTUnwrap(CGDataProvider(data: Data(pixels) as CFData))
        return try XCTUnwrap(CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 8,
            bytesPerRow: width,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        ))
    }

    private func makeOpenJPEGLosslessCodestream16(width: Int, height: Int, pixels: [UInt16]) throws -> Data {
        XCTAssertEqual(pixels.count, width * height)
        let executable = try DicomTestRuntimePreflight.requireExecutable(.opjCompress, named: "opj_compress")

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("jpeg2000_fixture_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let sourceURL = directory.appendingPathComponent("source.pgm")
        let encodedURL = directory.appendingPathComponent("source.j2k")
        var source = Data("P5\n\(width) \(height)\n65535\n".utf8)
        for pixel in pixels {
            source.append(UInt8(pixel >> 8))
            source.append(UInt8(pixel & 0xFF))
        }
        try source.write(to: sourceURL)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = ["-i", sourceURL.path, "-o", encodedURL.path, "-n", "1"]
        let errorPipe = Pipe()
        process.standardOutput = Pipe()
        process.standardError = errorPipe
        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let error = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "unknown error"
            XCTFail("opj_compress failed: \(error)")
            return Data()
        }
        return try Data(contentsOf: encodedURL)
    }

    private func encodeImage(_ image: CGImage, type: CFString, properties: CFDictionary? = nil) throws -> Data {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, type, 1, nil) else {
            throw XCTSkip("ImageIO cannot create destination for \(type)")
        }
        CGImageDestinationAddImage(destination, image, properties)
        guard CGImageDestinationFinalize(destination) else {
            throw XCTSkip("ImageIO cannot encode \(type)")
        }
        return data as Data
    }
}
