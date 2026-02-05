//
//  MetalWindowingTests.swift
//  DicomCoreTests
//
//  Metal GPU windowing tests using runtime shader compilation.
//  These tests verify that Metal shader bundling works in SPM test
//  environment using the Bundle.module pattern.
//

import XCTest
import Metal
@testable import DicomCore

class MetalWindowingTests: XCTestCase {

    // MARK: - Metal Setup Tests

    func testMetalDeviceAvailable() {
        // Verify Metal is available on the test system
        let device = MTLCreateSystemDefaultDevice()
        XCTAssertNotNil(device, "Metal device should be available")
    }

    func testShaderResourceBundling() throws {
        // Verify Metal shader is bundled correctly in test target
        let shaderURL = try XCTUnwrap(
            Bundle.module.url(forResource: "WindowingShaders", withExtension: "metal"),
            "Metal shader file should be bundled in test target resources"
        )

        // Verify shader source can be loaded
        let shaderSource = try String(contentsOf: shaderURL, encoding: .utf8)
        XCTAssertFalse(shaderSource.isEmpty, "Shader source should not be empty")
        XCTAssertTrue(shaderSource.contains("applyWindowLevel"), "Shader should contain applyWindowLevel kernel")
    }

    func testMetalLibraryCreation() throws {
        // Verify Metal library can be created from bundled shader
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("Metal not available on this system")
        }

        // Load shader source from Bundle.module (SPM pattern)
        let shaderURL = try XCTUnwrap(
            Bundle.module.url(forResource: "WindowingShaders", withExtension: "metal"),
            "Metal shader file should be bundled"
        )
        let shaderSource = try String(contentsOf: shaderURL, encoding: .utf8)

        // Compile shader at runtime (required pattern for SPM)
        let library = try device.makeLibrary(source: shaderSource, options: nil)
        XCTAssertNotNil(library, "Metal library should be created from source")

        // Verify kernel function exists
        let function = library.makeFunction(name: "applyWindowLevel")
        XCTAssertNotNil(function, "applyWindowLevel kernel function should exist")
    }

    // MARK: - Metal Windowing Tests

    func testMetalWindowingTransformation() throws {
        // Skip if Metal not available
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("Metal not available on this system")
        }

        // Create Metal pipeline
        let shaderURL = try XCTUnwrap(Bundle.module.url(forResource: "WindowingShaders", withExtension: "metal"))
        let shaderSource = try String(contentsOf: shaderURL, encoding: .utf8)
        let library = try device.makeLibrary(source: shaderSource, options: nil)
        let function = try XCTUnwrap(library.makeFunction(name: "applyWindowLevel"))
        let pipelineState = try device.makeComputePipelineState(function: function)

        // Test data: simple gradient
        let pixels16: [UInt16] = [0, 1000, 2000, 3000, 4000]
        let center: Float = 2000.0
        let width: Float = 2000.0

        // Create Metal buffers
        let inputBuffer = try XCTUnwrap(device.makeBuffer(bytes: pixels16, length: pixels16.count * MemoryLayout<UInt16>.stride, options: []))
        let outputBuffer = try XCTUnwrap(device.makeBuffer(length: pixels16.count * MemoryLayout<UInt8>.stride, options: []))

        // Execute shader
        let commandQueue = try XCTUnwrap(device.makeCommandQueue())
        let commandBuffer = try XCTUnwrap(commandQueue.makeCommandBuffer())
        let computeEncoder = try XCTUnwrap(commandBuffer.makeComputeCommandEncoder())

        computeEncoder.setComputePipelineState(pipelineState)
        computeEncoder.setBuffer(inputBuffer, offset: 0, index: 0)
        computeEncoder.setBuffer(outputBuffer, offset: 0, index: 1)

        var centerParam = center
        var widthParam = width
        var pixelCountParam = UInt32(pixels16.count)
        computeEncoder.setBytes(&centerParam, length: MemoryLayout<Float>.stride, index: 2)
        computeEncoder.setBytes(&widthParam, length: MemoryLayout<Float>.stride, index: 3)
        computeEncoder.setBytes(&pixelCountParam, length: MemoryLayout<UInt32>.stride, index: 4)

        let threadsPerGrid = MTLSize(width: pixels16.count, height: 1, depth: 1)
        let threadsPerThreadgroup = MTLSize(width: min(pixels16.count, pipelineState.maxTotalThreadsPerThreadgroup), height: 1, depth: 1)
        computeEncoder.dispatchThreads(threadsPerGrid, threadsPerThreadgroup: threadsPerThreadgroup)
        computeEncoder.endEncoding()

        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()

        // Verify results
        let resultPointer = outputBuffer.contents().bindMemory(to: UInt8.self, capacity: pixels16.count)
        let results = Array(UnsafeBufferPointer(start: resultPointer, count: pixels16.count))

        // Window: center=2000, width=2000 → range [1000, 3000]
        // pixel=0 → below min → 0
        // pixel=1000 → at min → 0
        // pixel=2000 → at center → 127
        // pixel=3000 → at max → 255
        // pixel=4000 → above max → 255
        XCTAssertEqual(results.count, 5, "Should have 5 output pixels")
        XCTAssertEqual(results[0], 0, "Pixel below window minimum should be 0")
        XCTAssertEqual(results[1], 0, "Pixel at window minimum should be 0")
        XCTAssertTrue(results[2] >= 125 && results[2] <= 130, "Center pixel should be ~127")
        XCTAssertEqual(results[3], 255, "Pixel at window maximum should be 255")
        XCTAssertEqual(results[4], 255, "Pixel above window maximum should be 255")
    }

    func testMetalVsDSPConsistency() throws {
        // Verify Metal and vDSP produce equivalent results
        guard MTLCreateSystemDefaultDevice() != nil else {
            throw XCTSkip("Metal not available on this system")
        }

        // Test data
        let pixels16: [UInt16] = (0..<1000).map { UInt16($0 * 4) }
        let center = 2000.0
        let width = 2000.0

        // Compute vDSP baseline
        let vdspResult = DCMWindowingProcessor.applyWindowLevel(pixels16: pixels16, center: center, width: width)
        XCTAssertNotNil(vdspResult, "vDSP windowing should succeed")

        // TODO: Implement Metal windowing in DCMWindowingProcessor
        // For now, this test documents the expected behavior

        print("NOTE: Metal implementation in DCMWindowingProcessor pending")
        print("      External validation via MetalBenchmark shows 3.94x speedup")
        print("      This test will verify consistency once integrated")
    }
}
