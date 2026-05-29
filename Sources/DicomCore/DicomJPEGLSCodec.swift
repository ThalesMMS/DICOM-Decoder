import Darwin
import Foundation

internal enum DicomJPEGLSCodec {
    struct DecodedFrame {
        let bytes: Data
        let width: Int
        let height: Int
        let bitsPerSample: Int
        let componentCount: Int
        let nearLossless: Int
    }

    static var isAvailable: Bool {
        CharLSLibrary.shared.isAvailable
    }

    static func decode(_ data: Data) throws -> DecodedFrame {
        let library = try CharLSLibrary.shared.require()
        guard let decoder = library.decoderCreate() else {
            throw DICOMError.imageProcessingFailed(operation: "JPEG-LS decode", reason: "CharLS decoder allocation failed")
        }
        defer { library.decoderDestroy(decoder) }

        try data.withUnsafeBytes { sourceBytes in
            guard let sourceAddress = sourceBytes.baseAddress else {
                throw DICOMError.invalidPixelData(reason: "JPEG-LS frame is empty")
            }
            try library.check(
                library.decoderSetSourceBuffer(decoder, sourceAddress, sourceBytes.count),
                operation: "set JPEG-LS source buffer"
            )
        }
        try library.check(library.decoderReadHeader(decoder), operation: "read JPEG-LS header")

        var frameInfo = CharLSFrameInfo()
        try withUnsafeMutablePointer(to: &frameInfo) { frameInfoPointer in
            try library.check(
                library.decoderGetFrameInfo(decoder, UnsafeMutableRawPointer(frameInfoPointer)),
                operation: "read JPEG-LS frame info"
            )
        }

        var nearLossless: Int32 = 0
        try library.check(library.decoderGetNearLossless(decoder, 0, &nearLossless), operation: "read JPEG-LS NEAR parameter")

        var destinationSize = 0
        try library.check(
            library.decoderGetDestinationSize(decoder, 0, &destinationSize),
            operation: "read JPEG-LS destination size"
        )
        guard destinationSize > 0 else {
            throw DICOMError.invalidPixelData(reason: "JPEG-LS decoder reported an empty destination buffer")
        }

        var decoded = Data(count: destinationSize)
        try decoded.withUnsafeMutableBytes { destinationBytes in
            guard let destinationAddress = destinationBytes.baseAddress else {
                throw DICOMError.memoryAllocationFailed(requestedSize: Int64(destinationSize))
            }
            try library.check(
                library.decoderDecodeToBuffer(decoder, destinationAddress, destinationSize, 0),
                operation: "decode JPEG-LS frame"
            )
        }

        return DecodedFrame(
            bytes: decoded,
            width: Int(frameInfo.width),
            height: Int(frameInfo.height),
            bitsPerSample: Int(frameInfo.bitsPerSample),
            componentCount: Int(frameInfo.componentCount),
            nearLossless: Int(nearLossless)
        )
    }

    static func encodeForTesting(
        bytes: Data,
        width: Int,
        height: Int,
        bitsPerSample: Int,
        componentCount: Int = 1,
        nearLossless: Int = 0
    ) throws -> Data {
        let library = try CharLSLibrary.shared.require()
        guard let encoder = library.encoderCreate() else {
            throw DICOMError.imageProcessingFailed(operation: "JPEG-LS encode", reason: "CharLS encoder allocation failed")
        }
        defer { library.encoderDestroy(encoder) }

        var frameInfo = CharLSFrameInfo(
            width: UInt32(width),
            height: UInt32(height),
            bitsPerSample: Int32(bitsPerSample),
            componentCount: Int32(componentCount)
        )
        try withUnsafePointer(to: &frameInfo) { frameInfoPointer in
            try library.check(
                library.encoderSetFrameInfo(encoder, UnsafeRawPointer(frameInfoPointer)),
                operation: "set JPEG-LS frame info"
            )
        }
        try library.check(library.encoderSetNearLossless(encoder, Int32(nearLossless)), operation: "set JPEG-LS NEAR parameter")
        try library.check(library.encoderSetInterleaveMode(encoder, componentCount == 1 ? 0 : 2), operation: "set JPEG-LS interleave mode")

        var estimatedSize = 0
        try library.check(library.encoderGetEstimatedDestinationSize(encoder, &estimatedSize), operation: "estimate JPEG-LS size")
        guard estimatedSize > 0 else {
            throw DICOMError.invalidPixelData(reason: "CharLS estimated an empty JPEG-LS output")
        }

        var encoded = Data(count: estimatedSize)
        try encoded.withUnsafeMutableBytes { destinationBytes in
            guard let destinationAddress = destinationBytes.baseAddress else {
                throw DICOMError.memoryAllocationFailed(requestedSize: Int64(estimatedSize))
            }
            try library.check(
                library.encoderSetDestinationBuffer(encoder, destinationAddress, estimatedSize),
                operation: "set JPEG-LS destination buffer"
            )
        }

        try bytes.withUnsafeBytes { sourceBytes in
            guard let sourceAddress = sourceBytes.baseAddress else {
                throw DICOMError.invalidPixelData(reason: "JPEG-LS source pixels are empty")
            }
            try library.check(
                library.encoderEncodeFromBuffer(encoder, sourceAddress, sourceBytes.count, 0),
                operation: "encode JPEG-LS frame"
            )
        }

        var bytesWritten = 0
        try library.check(library.encoderGetBytesWritten(encoder, &bytesWritten), operation: "read JPEG-LS encoded size")
        guard bytesWritten > 0, bytesWritten <= encoded.count else {
            throw DICOMError.invalidPixelData(reason: "CharLS returned invalid encoded size \(bytesWritten)")
        }
        encoded.removeSubrange(bytesWritten..<encoded.count)
        return encoded
    }
}

private struct CharLSFrameInfo {
    var width: UInt32 = 0
    var height: UInt32 = 0
    var bitsPerSample: Int32 = 0
    var componentCount: Int32 = 0
}

private final class CharLSLibrary {
    static let shared = CharLSLibrary()

    typealias DecoderCreate = @convention(c) () -> OpaquePointer?
    typealias DecoderDestroy = @convention(c) (OpaquePointer?) -> Void
    typealias DecoderSetSourceBuffer = @convention(c) (OpaquePointer, UnsafeRawPointer?, Int) -> Int32
    typealias DecoderReadHeader = @convention(c) (OpaquePointer) -> Int32
    typealias DecoderGetFrameInfo = @convention(c) (OpaquePointer, UnsafeMutableRawPointer?) -> Int32
    typealias DecoderGetNearLossless = @convention(c) (OpaquePointer, Int32, UnsafeMutablePointer<Int32>) -> Int32
    typealias DecoderGetDestinationSize = @convention(c) (OpaquePointer, UInt32, UnsafeMutablePointer<Int>) -> Int32
    typealias DecoderDecodeToBuffer = @convention(c) (OpaquePointer, UnsafeMutableRawPointer?, Int, UInt32) -> Int32

    typealias EncoderCreate = @convention(c) () -> OpaquePointer?
    typealias EncoderDestroy = @convention(c) (OpaquePointer?) -> Void
    typealias EncoderSetFrameInfo = @convention(c) (OpaquePointer, UnsafeRawPointer?) -> Int32
    typealias EncoderSetNearLossless = @convention(c) (OpaquePointer, Int32) -> Int32
    typealias EncoderSetInterleaveMode = @convention(c) (OpaquePointer, Int32) -> Int32
    typealias EncoderGetEstimatedDestinationSize = @convention(c) (OpaquePointer, UnsafeMutablePointer<Int>) -> Int32
    typealias EncoderSetDestinationBuffer = @convention(c) (OpaquePointer, UnsafeMutableRawPointer?, Int) -> Int32
    typealias EncoderEncodeFromBuffer = @convention(c) (OpaquePointer, UnsafeRawPointer?, Int, UInt32) -> Int32
    typealias EncoderGetBytesWritten = @convention(c) (OpaquePointer, UnsafeMutablePointer<Int>) -> Int32
    typealias GetErrorMessage = @convention(c) (Int32) -> UnsafePointer<CChar>?

    let handle: UnsafeMutableRawPointer?

    let decoderCreate: DecoderCreate
    let decoderDestroy: DecoderDestroy
    let decoderSetSourceBuffer: DecoderSetSourceBuffer
    let decoderReadHeader: DecoderReadHeader
    let decoderGetFrameInfo: DecoderGetFrameInfo
    let decoderGetNearLossless: DecoderGetNearLossless
    let decoderGetDestinationSize: DecoderGetDestinationSize
    let decoderDecodeToBuffer: DecoderDecodeToBuffer

    let encoderCreate: EncoderCreate
    let encoderDestroy: EncoderDestroy
    let encoderSetFrameInfo: EncoderSetFrameInfo
    let encoderSetNearLossless: EncoderSetNearLossless
    let encoderSetInterleaveMode: EncoderSetInterleaveMode
    let encoderGetEstimatedDestinationSize: EncoderGetEstimatedDestinationSize
    let encoderSetDestinationBuffer: EncoderSetDestinationBuffer
    let encoderEncodeFromBuffer: EncoderEncodeFromBuffer
    let encoderGetBytesWritten: EncoderGetBytesWritten
    let getErrorMessage: GetErrorMessage

    var isAvailable: Bool {
        handle != nil
    }

    private init() {
        handle = Self.openLibrary()

        decoderCreate = Self.load("charls_jpegls_decoder_create", from: handle, as: DecoderCreate.self)
        decoderDestroy = Self.load("charls_jpegls_decoder_destroy", from: handle, as: DecoderDestroy.self)
        decoderSetSourceBuffer = Self.load("charls_jpegls_decoder_set_source_buffer", from: handle, as: DecoderSetSourceBuffer.self)
        decoderReadHeader = Self.load("charls_jpegls_decoder_read_header", from: handle, as: DecoderReadHeader.self)
        decoderGetFrameInfo = Self.load("charls_jpegls_decoder_get_frame_info", from: handle, as: DecoderGetFrameInfo.self)
        decoderGetNearLossless = Self.load("charls_jpegls_decoder_get_near_lossless", from: handle, as: DecoderGetNearLossless.self)
        decoderGetDestinationSize = Self.load("charls_jpegls_decoder_get_destination_size", from: handle, as: DecoderGetDestinationSize.self)
        decoderDecodeToBuffer = Self.load("charls_jpegls_decoder_decode_to_buffer", from: handle, as: DecoderDecodeToBuffer.self)

        encoderCreate = Self.load("charls_jpegls_encoder_create", from: handle, as: EncoderCreate.self)
        encoderDestroy = Self.load("charls_jpegls_encoder_destroy", from: handle, as: EncoderDestroy.self)
        encoderSetFrameInfo = Self.load("charls_jpegls_encoder_set_frame_info", from: handle, as: EncoderSetFrameInfo.self)
        encoderSetNearLossless = Self.load("charls_jpegls_encoder_set_near_lossless", from: handle, as: EncoderSetNearLossless.self)
        encoderSetInterleaveMode = Self.load("charls_jpegls_encoder_set_interleave_mode", from: handle, as: EncoderSetInterleaveMode.self)
        encoderGetEstimatedDestinationSize = Self.load("charls_jpegls_encoder_get_estimated_destination_size", from: handle, as: EncoderGetEstimatedDestinationSize.self)
        encoderSetDestinationBuffer = Self.load("charls_jpegls_encoder_set_destination_buffer", from: handle, as: EncoderSetDestinationBuffer.self)
        encoderEncodeFromBuffer = Self.load("charls_jpegls_encoder_encode_from_buffer", from: handle, as: EncoderEncodeFromBuffer.self)
        encoderGetBytesWritten = Self.load("charls_jpegls_encoder_get_bytes_written", from: handle, as: EncoderGetBytesWritten.self)
        getErrorMessage = Self.load("charls_get_error_message", from: handle, as: GetErrorMessage.self)
    }

    deinit {
        if let handle {
            dlclose(handle)
        }
    }

    func require() throws -> CharLSLibrary {
        guard isAvailable else {
            throw DICOMError.unsupportedTransferSyntax(syntax: "JPEG-LS requires the CharLS runtime library")
        }
        return self
    }

    func check(_ code: Int32, operation: String) throws {
        guard code == 0 else {
            let message = getErrorMessage(code).map { String(cString: $0) } ?? "CharLS error \(code)"
            throw DICOMError.imageProcessingFailed(operation: operation, reason: message)
        }
    }

    private static func openLibrary() -> UnsafeMutableRawPointer? {
        let candidates = [
            "/opt/homebrew/lib/libcharls.2.dylib",
            "/opt/homebrew/lib/libcharls.dylib",
            "/usr/local/lib/libcharls.2.dylib",
            "/usr/local/lib/libcharls.dylib",
            "libcharls.2.dylib",
            "libcharls.dylib"
        ]
        for candidate in candidates {
            if let handle = dlopen(candidate, RTLD_NOW | RTLD_LOCAL) {
                return handle
            }
        }
        return nil
    }

    private static func load<T>(_ name: String, from handle: UnsafeMutableRawPointer?, as type: T.Type) -> T {
        guard let handle, let symbol = dlsym(handle, name) else {
            return unsafeBitCast(Self.missingSymbol, to: type)
        }
        return unsafeBitCast(symbol, to: type)
    }

    private static let missingSymbol: @convention(c) () -> Void = {
        fatalError("Required CharLS symbol is unavailable")
    }
}
