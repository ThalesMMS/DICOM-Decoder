import Darwin
import Foundation

internal enum DicomJPEG2000Codec {
    struct DecodedFrame {
        let bytes: Data
        let width: Int
        let height: Int
        let bitsPerSample: Int
        let componentCount: Int
    }

    struct DecodedVolume {
        let voxels: Data
        let width: Int
        let height: Int
        let depth: Int
        let bitsPerSample: Int
        let isSigned: Bool
    }

    static var isAvailable: Bool {
        OpenJPEGLibrary.shared.isAvailable
    }

    static func decode(_ data: Data) throws -> DecodedFrame {
        try decodeImage(data) { image in
            try makeFrame(from: image)
        }
    }

    static func decodeVolume(_ data: Data) throws -> DecodedVolume {
        try decodeImage(data) { image in
            try makeVolume(from: image)
        }
    }

    private static func decodeImage<T>(_ data: Data, body: (OpenJPEGImage) throws -> T) throws -> T {
        let library = try OpenJPEGLibrary.shared.require()
        let format = isJP2File(data) ? OpenJPEGLibrary.codecJP2 : OpenJPEGLibrary.codecJ2K
        guard let codec = library.createDecompress(format) else {
            throw DICOMError.imageProcessingFailed(operation: "JPEG 2000 decode", reason: "OpenJPEG decoder allocation failed")
        }
        defer { library.destroyCodec(codec) }

        // OpenJPEG decoder parameters include fixed-size C path buffers; keep this raw allocation isolated.
        let parameterByteCount = 16_384
        let parameters = UnsafeMutableRawPointer.allocate(byteCount: parameterByteCount, alignment: 16)
        parameters.initializeMemory(as: UInt8.self, repeating: 0, count: parameterByteCount)
        defer { parameters.deallocate() }

        library.setDefaultDecoderParameters(parameters)
        try library.check(library.setupDecoder(codec, parameters), operation: "setup JPEG 2000 decoder")

        let temporaryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("dicom_jpeg2000_\(UUID().uuidString).\(format == OpenJPEGLibrary.codecJP2 ? "jp2" : "j2k")")
        try data.write(to: temporaryURL)
        defer { try? FileManager.default.removeItem(at: temporaryURL) }

        guard let stream = temporaryURL.path.withCString({ library.streamCreateDefaultFile($0, 1) }) else {
            throw DICOMError.imageProcessingFailed(operation: "JPEG 2000 decode", reason: "OpenJPEG stream allocation failed")
        }
        defer { library.streamDestroy(stream) }

        var imageRawPointer: UnsafeMutableRawPointer?
        try library.check(library.readHeader(stream, codec, &imageRawPointer), operation: "read JPEG 2000 header")
        guard let imageRawPointer else {
            throw DICOMError.invalidPixelData(reason: "OpenJPEG did not return image metadata")
        }
        defer { library.imageDestroy(imageRawPointer) }
        let imagePointer = imageRawPointer.assumingMemoryBound(to: OpenJPEGImage.self)

        try library.check(library.decode(codec, stream, imageRawPointer), operation: "decode JPEG 2000 image")
        try library.check(library.endDecompress(codec, stream), operation: "finish JPEG 2000 decode")

        return try body(imagePointer.pointee)
    }

    private static func makeFrame(from image: OpenJPEGImage) throws -> DecodedFrame {
        let componentCount = Int(image.numcomps)
        guard componentCount == 1 || componentCount == 3 else {
            throw DICOMError.invalidPixelData(reason: "JPEG 2000 component count \(componentCount) is unsupported")
        }
        guard let componentsPointer = image.comps else {
            throw DICOMError.invalidPixelData(reason: "JPEG 2000 image has no component buffer")
        }

        let components = UnsafeBufferPointer(start: componentsPointer, count: componentCount)
        let first = components[0]
        let width = Int(first.w)
        let height = Int(first.h)
        let bitsPerSample = Int(first.prec)
        let pixelCount = width * height
        guard width > 0, height > 0, pixelCount > 0 else {
            throw DICOMError.invalidPixelData(reason: "JPEG 2000 image dimensions are invalid")
        }
        guard bitsPerSample > 0, bitsPerSample <= 16 else {
            throw DICOMError.invalidPixelData(reason: "JPEG 2000 precision \(bitsPerSample) is unsupported")
        }

        for component in components {
            guard Int(component.w) == width, Int(component.h) == height, Int(component.prec) == bitsPerSample else {
                throw DICOMError.invalidPixelData(reason: "JPEG 2000 components do not share dimensions and precision")
            }
            guard component.data != nil else {
                throw DICOMError.invalidPixelData(reason: "JPEG 2000 component data is missing")
            }
        }

        if componentCount == 1 {
            let component = components[0]
            let samples = UnsafeBufferPointer(start: component.data, count: pixelCount)
            if bitsPerSample <= 8 {
                return DecodedFrame(
                    bytes: Data(samples.map { byteValue(from: $0, signed: component.sgnd != 0) }),
                    width: width,
                    height: height,
                    bitsPerSample: bitsPerSample,
                    componentCount: 1
                )
            }

            var output = Data()
            output.reserveCapacity(pixelCount * MemoryLayout<UInt16>.size)
            for sample in samples {
                let value = wordValue(from: sample, signed: component.sgnd != 0)
                appendLittleEndianWord(value, to: &output)
            }
            return DecodedFrame(
                bytes: output,
                width: width,
                height: height,
                bitsPerSample: bitsPerSample,
                componentCount: 1
            )
        }

        guard bitsPerSample <= 8 else {
            throw DICOMError.invalidPixelData(reason: "JPEG 2000 color output above 8 bits per component is unsupported")
        }

        var output = [UInt8](repeating: 0, count: pixelCount * 3)
        for componentIndex in 0..<3 {
            let component = components[componentIndex]
            let samples = UnsafeBufferPointer(start: component.data, count: pixelCount)
            for pixelIndex in 0..<pixelCount {
                output[pixelIndex * 3 + componentIndex] = byteValue(from: samples[pixelIndex], signed: component.sgnd != 0)
            }
        }
        return DecodedFrame(
            bytes: Data(output),
            width: width,
            height: height,
            bitsPerSample: bitsPerSample,
            componentCount: 3
        )
    }

    private static func makeVolume(from image: OpenJPEGImage) throws -> DecodedVolume {
        let componentCount = Int(image.numcomps)
        guard componentCount > 0 else {
            throw DICOMError.invalidPixelData(reason: "JPEG 2000 volume has no components")
        }
        guard let componentsPointer = image.comps else {
            throw DICOMError.invalidPixelData(reason: "JPEG 2000 volume has no component buffer")
        }

        let components = UnsafeBufferPointer(start: componentsPointer, count: componentCount)
        let first = components[0]
        let width = Int(first.w)
        let height = Int(first.h)
        let bitsPerSample = Int(first.prec)
        let pixelCount = width * height
        let isSigned = first.sgnd != 0
        guard width > 0, height > 0, pixelCount > 0 else {
            throw DICOMError.invalidPixelData(reason: "JPEG 2000 volume dimensions are invalid")
        }
        guard bitsPerSample > 0, bitsPerSample <= 16 else {
            throw DICOMError.invalidPixelData(reason: "JPEG 2000 volume precision \(bitsPerSample) is unsupported")
        }

        for component in components {
            guard Int(component.w) == width, Int(component.h) == height, Int(component.prec) == bitsPerSample else {
                throw DICOMError.invalidPixelData(reason: "JPEG 2000 volume components do not share dimensions and precision")
            }
            guard (component.sgnd != 0) == isSigned else {
                throw DICOMError.invalidPixelData(reason: "JPEG 2000 volume components mix signed and unsigned samples")
            }
            guard component.data != nil else {
                throw DICOMError.invalidPixelData(reason: "JPEG 2000 volume component data is missing")
            }
        }

        var output = Data()
        output.reserveCapacity(pixelCount * componentCount * MemoryLayout<UInt16>.size)
        for component in components {
            let samples = UnsafeBufferPointer(start: component.data, count: pixelCount)
            for sample in samples {
                appendLittleEndianWord(wordValue(from: sample, signed: isSigned), to: &output)
            }
        }

        return DecodedVolume(
            voxels: output,
            width: width,
            height: height,
            depth: componentCount,
            bitsPerSample: bitsPerSample,
            isSigned: isSigned
        )
    }

    private static func byteValue(from sample: Int32, signed: Bool) -> UInt8 {
        if signed {
            return UInt8(bitPattern: Int8(clamping: sample))
        }
        return UInt8(clamping: sample)
    }

    private static func wordValue(from sample: Int32, signed: Bool) -> UInt16 {
        if signed {
            return UInt16(bitPattern: Int16(clamping: sample))
        }
        return UInt16(clamping: sample)
    }

    private static func appendLittleEndianWord(_ value: UInt16, to data: inout Data) {
        data.append(UInt8(value & 0xFF))
        data.append(UInt8(value >> 8))
    }

    private static func isJP2File(_ data: Data) -> Bool {
        let signature: [UInt8] = [0x00, 0x00, 0x00, 0x0C, 0x6A, 0x50, 0x20, 0x20]
        return data.count >= signature.count && Array(data.prefix(signature.count)) == signature
    }
}

private struct OpenJPEGImageComponent {
    var dx: UInt32
    var dy: UInt32
    var w: UInt32
    var h: UInt32
    var x0: UInt32
    var y0: UInt32
    var prec: UInt32
    var bpp: UInt32
    var sgnd: UInt32
    var resno_decoded: UInt32
    var factor: UInt32
    var data: UnsafeMutablePointer<Int32>?
    var alpha: UInt16
}

private struct OpenJPEGImage {
    var x0: UInt32
    var y0: UInt32
    var x1: UInt32
    var y1: UInt32
    var numcomps: UInt32
    var colorSpace: Int32
    var comps: UnsafeMutablePointer<OpenJPEGImageComponent>?
    var iccProfileBuffer: UnsafeMutablePointer<UInt8>?
    var iccProfileLength: UInt32
}

private final class OpenJPEGLibrary {
    static let shared = OpenJPEGLibrary()

    static let codecJ2K: Int32 = 0
    static let codecJP2: Int32 = 2

    typealias CreateDecompress = @convention(c) (Int32) -> OpaquePointer?
    typealias DestroyCodec = @convention(c) (OpaquePointer?) -> Void
    typealias SetDefaultDecoderParameters = @convention(c) (UnsafeMutableRawPointer?) -> Void
    typealias SetupDecoder = @convention(c) (OpaquePointer?, UnsafeMutableRawPointer?) -> Int32
    typealias StreamCreateDefaultFile = @convention(c) (UnsafePointer<CChar>?, Int32) -> OpaquePointer?
    typealias StreamDestroy = @convention(c) (OpaquePointer?) -> Void
    typealias ReadHeader = @convention(c) (OpaquePointer?, OpaquePointer?, UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> Int32
    typealias Decode = @convention(c) (OpaquePointer?, OpaquePointer?, UnsafeMutableRawPointer?) -> Int32
    typealias EndDecompress = @convention(c) (OpaquePointer?, OpaquePointer?) -> Int32
    typealias ImageDestroy = @convention(c) (UnsafeMutableRawPointer?) -> Void

    let handle: UnsafeMutableRawPointer?
    let createDecompress: CreateDecompress
    let destroyCodec: DestroyCodec
    let setDefaultDecoderParameters: SetDefaultDecoderParameters
    let setupDecoder: SetupDecoder
    let streamCreateDefaultFile: StreamCreateDefaultFile
    let streamDestroy: StreamDestroy
    let readHeader: ReadHeader
    let decode: Decode
    let endDecompress: EndDecompress
    let imageDestroy: ImageDestroy

    var isAvailable: Bool {
        handle != nil
    }

    private init() {
        handle = Self.openLibrary()
        createDecompress = Self.load("opj_create_decompress", from: handle, as: CreateDecompress.self)
        destroyCodec = Self.load("opj_destroy_codec", from: handle, as: DestroyCodec.self)
        setDefaultDecoderParameters = Self.load("opj_set_default_decoder_parameters", from: handle, as: SetDefaultDecoderParameters.self)
        setupDecoder = Self.load("opj_setup_decoder", from: handle, as: SetupDecoder.self)
        streamCreateDefaultFile = Self.load("opj_stream_create_default_file_stream", from: handle, as: StreamCreateDefaultFile.self)
        streamDestroy = Self.load("opj_stream_destroy", from: handle, as: StreamDestroy.self)
        readHeader = Self.load("opj_read_header", from: handle, as: ReadHeader.self)
        decode = Self.load("opj_decode", from: handle, as: Decode.self)
        endDecompress = Self.load("opj_end_decompress", from: handle, as: EndDecompress.self)
        imageDestroy = Self.load("opj_image_destroy", from: handle, as: ImageDestroy.self)
    }

    deinit {
        if let handle {
            dlclose(handle)
        }
    }

    func require() throws -> OpenJPEGLibrary {
        guard isAvailable else {
            throw DICOMError.unsupportedTransferSyntax(syntax: "JPEG 2000 requires the OpenJPEG runtime library")
        }
        return self
    }

    func check(_ code: Int32, operation: String) throws {
        guard code != 0 else {
            throw DICOMError.imageProcessingFailed(operation: operation, reason: "OpenJPEG returned failure")
        }
    }

    private static func openLibrary() -> UnsafeMutableRawPointer? {
        let candidates = [
            "/opt/homebrew/lib/libopenjp2.7.dylib",
            "/opt/homebrew/lib/libopenjp2.dylib",
            "/usr/local/lib/libopenjp2.7.dylib",
            "/usr/local/lib/libopenjp2.dylib",
            "libopenjp2.7.dylib",
            "libopenjp2.dylib"
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
        fatalError("Required OpenJPEG symbol is unavailable")
    }
}
