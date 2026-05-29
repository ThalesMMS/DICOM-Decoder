import Foundation

public enum DicomProgressiveUpdateQuality: String, Sendable, Equatable {
    case preview
    case refinement
    case final
}

public struct DicomProgressiveLayer: Sendable, Equatable {
    public let index: Int
    public let totalLayerCount: Int?
    public let quality: DicomProgressiveUpdateQuality
    public let byteRange: Range<Int>?
    public let fractionComplete: Double
    public let isFinal: Bool

    public init(index: Int,
                totalLayerCount: Int? = nil,
                quality: DicomProgressiveUpdateQuality,
                byteRange: Range<Int>? = nil,
                fractionComplete: Double,
                isFinal: Bool) {
        self.index = index
        self.totalLayerCount = totalLayerCount
        self.quality = quality
        self.byteRange = byteRange
        self.fractionComplete = fractionComplete
        self.isFinal = isFinal
    }
}

public struct DicomProgressiveVolumeUpdate: Sendable {
    public let layer: DicomProgressiveLayer
    public let volume: DicomSeriesVolume

    public init(layer: DicomProgressiveLayer, volume: DicomSeriesVolume) {
        self.layer = layer
        self.volume = volume
    }
}

public struct DicomJPIPReferencedPixelData: Sendable, Equatable {
    public let transferSyntax: DicomTransferSyntax
    public let pixelDataProviderURL: URL

    public init(transferSyntax: DicomTransferSyntax,
                pixelDataProviderURL: URL) throws {
        guard transferSyntax.usesPixelDataProviderURL else {
            throw DICOMError.unsupportedTransferSyntax(syntax: transferSyntax.rawValue)
        }
        self.transferSyntax = transferSyntax
        self.pixelDataProviderURL = pixelDataProviderURL
    }

    public init(decoder: DCMDecoder) throws {
        guard let transferSyntaxUID = decoder.info(for: .transferSyntaxUID).nilIfBlank,
              let transferSyntax = DicomTransferSyntax(uid: transferSyntaxUID) else {
            throw DICOMError.missingRequiredTag(tag: "0002,0010", description: "Transfer Syntax UID")
        }
        guard let urlString = decoder.info(for: .pixelDataProviderURL).nilIfBlank,
              let url = URL(string: urlString) else {
            throw DICOMError.missingRequiredTag(tag: "0028,7FE0", description: "Pixel Data Provider URL")
        }
        try self.init(transferSyntax: transferSyntax, pixelDataProviderURL: url)
    }

    public func makeVolumeRequest() -> DicomJPIPRequest {
        DicomJPIPRequest(pixelDataProviderURL: pixelDataProviderURL, resource: .volume)
    }
}

public struct DicomJPIPRequest: Sendable, Equatable {
    public enum Resource: Sendable, Equatable {
        case frame(index: Int)
        case volume
    }

    public let pixelDataProviderURL: URL
    public let resource: Resource
    public let requestedLayerRange: Range<Int>?

    public init(pixelDataProviderURL: URL,
                resource: Resource,
                requestedLayerRange: Range<Int>? = nil) {
        self.pixelDataProviderURL = pixelDataProviderURL
        self.resource = resource
        self.requestedLayerRange = requestedLayerRange
    }
}

public struct DicomJPIPLayerPayload: Sendable, Equatable {
    public let layer: DicomProgressiveLayer
    public let data: Data

    public init(layer: DicomProgressiveLayer, data: Data) {
        self.layer = layer
        self.data = data
    }
}

public protocol DicomJPIPTransport: Sendable {
    func payloads(for request: DicomJPIPRequest) -> AsyncThrowingStream<DicomJPIPLayerPayload, Error>
}

public struct DicomJPIPClient: Sendable {
    private let transport: any DicomJPIPTransport
    private let bufferingPolicy: AsyncThrowingStream<DicomProgressiveVolumeUpdate, Error>.Continuation.BufferingPolicy

    public init(
        transport: any DicomJPIPTransport,
        bufferingPolicy: AsyncThrowingStream<DicomProgressiveVolumeUpdate, Error>.Continuation.BufferingPolicy = .bufferingNewest(1)
    ) {
        self.transport = transport
        self.bufferingPolicy = bufferingPolicy
    }

    public func volumeUpdates(
        for reference: DicomJPIPReferencedPixelData,
        decode: @escaping @Sendable (DicomJPIPLayerPayload) async throws -> DicomSeriesVolume
    ) -> AsyncThrowingStream<DicomProgressiveVolumeUpdate, Error> {
        volumeUpdates(for: reference.makeVolumeRequest(), decode: decode)
    }

    public func volumeUpdates(
        for request: DicomJPIPRequest,
        decode: @escaping @Sendable (DicomJPIPLayerPayload) async throws -> DicomSeriesVolume
    ) -> AsyncThrowingStream<DicomProgressiveVolumeUpdate, Error> {
        AsyncThrowingStream(bufferingPolicy: bufferingPolicy) { continuation in
            let task = Task {
                do {
                    for try await payload in transport.payloads(for: request) {
                        try Task.checkCancellation()
                        let volume = try await decode(payload)
                        try Task.checkCancellation()
                        continuation.yield(DicomProgressiveVolumeUpdate(layer: payload.layer, volume: volume))
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
            }
        }
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "\0")))
        return trimmed.isEmpty ? nil : trimmed
    }
}
