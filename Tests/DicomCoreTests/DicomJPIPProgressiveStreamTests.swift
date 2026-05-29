import Foundation
import XCTest
@testable import DicomCore
import simd

final class DicomJPIPProgressiveStreamTests: XCTestCase {
    func testReferencedPixelDataObjectLoadsWithoutLocalPixelData() throws {
        let url = try makeTemporaryFileURL()
        defer { try? FileManager.default.removeItem(at: url) }

        try makeJPIPReferencedDICOM(providerURL: "https://pacs.example.test/jpip?target=volume.jp2")
            .write(to: url)

        let decoder = try DCMDecoder(contentsOf: url)
        let reference = try DicomJPIPReferencedPixelData(decoder: decoder)

        XCTAssertEqual(reference.transferSyntax, .jpipReferenced)
        XCTAssertEqual(reference.pixelDataProviderURL.absoluteString, "https://pacs.example.test/jpip?target=volume.jp2")
        XCTAssertEqual(reference.makeVolumeRequest().resource, .volume)
    }

    func testJPIPClientYieldsProgressiveVolumeUpdatesInOrder() async throws {
        let request = DicomJPIPRequest(
            pixelDataProviderURL: try XCTUnwrap(URL(string: "https://pacs.example.test/jpip?target=volume.jp2")),
            resource: .volume
        )
        let payloads = [
            makePayload(index: 0, quality: .preview, fraction: 0.25, final: false, voxelValue: 10),
            makePayload(index: 1, quality: .refinement, fraction: 0.75, final: false, voxelValue: 20),
            makePayload(index: 2, quality: .final, fraction: 1.0, final: true, voxelValue: 30)
        ]
        let client = DicomJPIPClient(
            transport: FakeJPIPTransport(payloads: payloads),
            bufferingPolicy: .unbounded
        )

        var received: [DicomProgressiveVolumeUpdate] = []
        for try await update in client.volumeUpdates(for: request, decode: { payload in
            try await Self.decodeSyntheticVolume(payload)
        }) {
            received.append(update)
        }

        XCTAssertEqual(received.map(\.layer.index), [0, 1, 2])
        XCTAssertEqual(received.map(\.layer.quality), [.preview, .refinement, .final])
        XCTAssertEqual(received.last?.layer.isFinal, true)
        XCTAssertEqual(try firstVoxelValue(in: try XCTUnwrap(received.last?.volume)), 30)
    }

    func testJPIPClientCancelsTransportWhenConsumerIsCancelled() async throws {
        let request = DicomJPIPRequest(
            pixelDataProviderURL: try XCTUnwrap(URL(string: "https://pacs.example.test/jpip?target=volume.jp2")),
            resource: .volume
        )
        let probe = TerminationProbe()
        var payloads: [DicomJPIPLayerPayload] = []
        for index in 0..<20 {
            let isFinal = index == 19
            payloads.append(
                makePayload(index: index,
                            quality: isFinal ? .final : .refinement,
                            fraction: Double(index + 1) / 20.0,
                            final: isFinal,
                            voxelValue: UInt8(index))
            )
        }
        let client = DicomJPIPClient(
            transport: FakeJPIPTransport(payloads: payloads, delayNanoseconds: 5_000_000, probe: probe)
        )
        let stream = client.volumeUpdates(for: request, decode: { payload in
            try await Self.decodeSyntheticVolume(payload)
        })

        let task = Task {
            for try await _ in stream {
                try Task.checkCancellation()
            }
        }

        try await Task.sleep(nanoseconds: 20_000_000)
        task.cancel()

        _ = try? await task.value

        let didTerminate = await probe.waitUntilTerminated()
        XCTAssertTrue(didTerminate)
    }

    private func makePayload(index: Int,
                             quality: DicomProgressiveUpdateQuality,
                             fraction: Double,
                             final: Bool,
                             voxelValue: UInt8) -> DicomJPIPLayerPayload {
        DicomJPIPLayerPayload(
            layer: DicomProgressiveLayer(
                index: index,
                totalLayerCount: 3,
                quality: quality,
                byteRange: index..<(index + 1),
                fractionComplete: fraction,
                isFinal: final
            ),
            data: Data([voxelValue])
        )
    }

    private static func decodeSyntheticVolume(_ payload: DicomJPIPLayerPayload) async throws -> DicomSeriesVolume {
        await Task.yield()
        let voxel = UInt16(payload.data.first ?? 0)
        let voxels = [voxel, voxel, voxel, voxel].withUnsafeBytes { Data($0) }
        return DicomSeriesVolume(
            voxels: voxels,
            width: 2,
            height: 2,
            depth: 1,
            spacing: SIMD3<Double>(1, 1, 1),
            orientation: matrix_identity_double3x3,
            origin: SIMD3<Double>(0, 0, 0),
            rescaleSlope: 1,
            rescaleIntercept: 0,
            bitsAllocated: 16,
            isSignedPixel: false,
            seriesDescription: "Progressive JPIP fixture",
            modality: "CT"
        )
    }

    private func firstVoxelValue(in volume: DicomSeriesVolume) throws -> UInt16 {
        try XCTUnwrap(volume.voxels.withUnsafeBytes { buffer in
            buffer.bindMemory(to: UInt16.self).first
        })
    }

    private func makeTemporaryFileURL() throws -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("DicomJPIPProgressiveStreamTests-\(UUID().uuidString).dcm")
    }

    private func makeJPIPReferencedDICOM(providerURL: String) -> Data {
        var data = Data(repeating: 0, count: 128)
        data.append(contentsOf: "DICM".utf8)
        appendTag(&data, group: 0x0002, element: 0x0010, vr: "UI", value: DicomTransferSyntax.jpipReferenced.rawValue)
        appendTag(&data, group: 0x0028, element: 0x0002, vr: "US", value: UInt16(1))
        appendTag(&data, group: 0x0028, element: 0x0004, vr: "CS", value: "MONOCHROME2")
        appendTag(&data, group: 0x0028, element: 0x0010, vr: "US", value: UInt16(2))
        appendTag(&data, group: 0x0028, element: 0x0011, vr: "US", value: UInt16(2))
        appendTag(&data, group: 0x0028, element: 0x0100, vr: "US", value: UInt16(16))
        appendTag(&data, group: 0x0028, element: 0x0101, vr: "US", value: UInt16(16))
        appendTag(&data, group: 0x0028, element: 0x0102, vr: "US", value: UInt16(15))
        appendTag(&data, group: 0x0028, element: 0x0103, vr: "US", value: UInt16(0))
        appendTag(&data, group: 0x0028, element: 0x7FE0, vr: "UR", value: providerURL)
        return data
    }

    private func appendTag(_ data: inout Data, group: UInt16, element: UInt16, vr: String, value: String) {
        var bytes = Data(value.utf8)
        if bytes.count % 2 != 0 {
            bytes.append(0x20)
        }
        appendTagHeader(&data, group: group, element: element, vr: vr, length: UInt32(bytes.count))
        data.append(bytes)
    }

    private func appendTag(_ data: inout Data, group: UInt16, element: UInt16, vr: String, value: UInt16) {
        var value = value.littleEndian
        appendTagHeader(&data, group: group, element: element, vr: vr, length: 2)
        withUnsafeBytes(of: &value) { data.append(contentsOf: $0) }
    }

    private func appendTagHeader(_ data: inout Data,
                                 group: UInt16,
                                 element: UInt16,
                                 vr: String,
                                 length: UInt32) {
        var littleGroup = group.littleEndian
        var littleElement = element.littleEndian
        data.append(Data(bytes: &littleGroup, count: 2))
        data.append(Data(bytes: &littleElement, count: 2))
        data.append(contentsOf: vr.utf8)
        if ["OB", "OW", "OV", "SQ", "UN", "UR", "UT"].contains(vr) {
            data.append(contentsOf: [0x00, 0x00])
            var littleLength = length.littleEndian
            data.append(Data(bytes: &littleLength, count: 4))
        } else {
            var shortLength = UInt16(length).littleEndian
            data.append(Data(bytes: &shortLength, count: 2))
        }
    }
}

private struct FakeJPIPTransport: DicomJPIPTransport {
    let payloads: [DicomJPIPLayerPayload]
    var delayNanoseconds: UInt64 = 0
    var probe: TerminationProbe?

    func payloads(for request: DicomJPIPRequest) -> AsyncThrowingStream<DicomJPIPLayerPayload, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for payload in self.payloads {
                        try Task.checkCancellation()
                        if delayNanoseconds > 0 {
                            try await Task.sleep(nanoseconds: delayNanoseconds)
                        }
                        continuation.yield(payload)
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish(throwing: CancellationError())
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { @Sendable _ in
                task.cancel()
                if let probe {
                    Task {
                        await probe.markTerminated()
                    }
                }
            }
        }
    }
}

private actor TerminationProbe {
    private var terminated = false

    func markTerminated() {
        terminated = true
    }

    func waitUntilTerminated() async -> Bool {
        for _ in 0..<100 {
            if terminated {
                return true
            }
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
        return terminated
    }
}
