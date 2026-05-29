import CoreGraphics
import Foundation
import ImageIO

public enum DicomPrintTag {
    public static let numberOfCopies = 0x2000_0010
    public static let printPriority = 0x2000_0020
    public static let mediumType = 0x2000_0030
    public static let filmDestination = 0x2000_0040
    public static let filmSessionLabel = 0x2000_0050
    public static let imageDisplayFormat = 0x2010_0010
    public static let filmOrientation = 0x2010_0040
    public static let filmSizeID = 0x2010_0050
    public static let magnificationType = 0x2010_0060
    public static let borderDensity = 0x2010_0100
    public static let emptyImageDensity = 0x2010_0110
    public static let trim = 0x2010_0140
    public static let configurationInformation = 0x2010_0150
    public static let referencedFilmSessionSequence = 0x2010_0500
    public static let referencedImageBoxSequence = 0x2010_0510
    public static let imagePosition = 0x2020_0010
    public static let basicGrayscaleImageSequence = 0x2020_0110
}

public enum DicomPrintPriority: String, Codable, Equatable, Sendable {
    case low = "LOW"
    case medium = "MED"
    case high = "HIGH"
}

public enum DicomFilmOrientation: String, Codable, Equatable, Sendable {
    case portrait = "PORTRAIT"
    case landscape = "LANDSCAPE"
}

public enum DicomFilmDestination: String, Codable, Equatable, Sendable {
    case magazine = "MAGAZINE"
    case processor = "PROCESSOR"
    case bin = "BIN"
}

public enum DicomPrintManagementError: Error, Equatable, LocalizedError, Sendable {
    case emptyImageList
    case invalidImagePosition(Int)
    case unsupportedSnapshotData

    public var errorDescription: String? {
        switch self {
        case .emptyImageList:
            return "A print job must contain at least one image box."
        case .invalidImagePosition(let position):
            return "Invalid image box position \(position)."
        case .unsupportedSnapshotData:
            return "Snapshot data could not be decoded into an RGB bitmap."
        }
    }
}

public struct DicomFilmSession: Equatable, Sendable {
    public var numberOfCopies: Int
    public var printPriority: DicomPrintPriority
    public var mediumType: String
    public var filmDestination: DicomFilmDestination
    public var label: String?

    public init(numberOfCopies: Int = 1,
                printPriority: DicomPrintPriority = .medium,
                mediumType: String = "BLUE FILM",
                filmDestination: DicomFilmDestination = .magazine,
                label: String? = nil) {
        self.numberOfCopies = max(1, numberOfCopies)
        self.printPriority = printPriority
        self.mediumType = mediumType
        self.filmDestination = filmDestination
        self.label = label
    }

    public var dataSet: DicomDataSet {
        DicomDataSet(elements: [
            printString(DicomPrintTag.numberOfCopies, .IS, String(numberOfCopies)),
            printString(DicomPrintTag.printPriority, .CS, printPriority.rawValue),
            printString(DicomPrintTag.mediumType, .CS, mediumType),
            printString(DicomPrintTag.filmDestination, .CS, filmDestination.rawValue),
            printString(DicomPrintTag.filmSessionLabel, .LO, label)
        ].filter { !$0.isEmptyValue })
    }
}

public struct DicomFilmBox: Equatable, Sendable {
    public var imageDisplayFormat: String
    public var orientation: DicomFilmOrientation
    public var filmSizeID: String
    public var magnificationType: String?
    public var borderDensity: String?
    public var emptyImageDensity: String?
    public var trim: Bool
    public var configurationInformation: String?

    public init(imageDisplayFormat: String = "STANDARD\\1,1",
                orientation: DicomFilmOrientation = .portrait,
                filmSizeID: String = "8INX10IN",
                magnificationType: String? = "REPLICATE",
                borderDensity: String? = "BLACK",
                emptyImageDensity: String? = "BLACK",
                trim: Bool = false,
                configurationInformation: String? = nil) {
        self.imageDisplayFormat = imageDisplayFormat
        self.orientation = orientation
        self.filmSizeID = filmSizeID
        self.magnificationType = magnificationType
        self.borderDensity = borderDensity
        self.emptyImageDensity = emptyImageDensity
        self.trim = trim
        self.configurationInformation = configurationInformation
    }

    public func dataSet(referencingFilmSessionUID filmSessionUID: String) -> DicomDataSet {
        DicomDataSet(elements: [
            printString(DicomPrintTag.imageDisplayFormat, .ST, imageDisplayFormat),
            printString(DicomPrintTag.filmOrientation, .CS, orientation.rawValue),
            printString(DicomPrintTag.filmSizeID, .CS, filmSizeID),
            printString(DicomPrintTag.magnificationType, .CS, magnificationType),
            printString(DicomPrintTag.borderDensity, .CS, borderDensity),
            printString(DicomPrintTag.emptyImageDensity, .CS, emptyImageDensity),
            printString(DicomPrintTag.trim, .CS, trim ? "YES" : "NO"),
            printString(DicomPrintTag.configurationInformation, .ST, configurationInformation),
            printSequence(DicomPrintTag.referencedFilmSessionSequence, [
                referenceDataSet(
                    sopClassUID: DicomNetworkUID.basicFilmSessionSOPClass,
                    sopInstanceUID: filmSessionUID
                )
            ])
        ].filter { !$0.isEmptyValue })
    }
}

public struct DicomPrintTemplate: Equatable, Sendable {
    public var filmSession: DicomFilmSession
    public var filmBox: DicomFilmBox
    public var imageSize: DicomImageSize?

    public init(filmSession: DicomFilmSession = DicomFilmSession(),
                filmBox: DicomFilmBox = DicomFilmBox(),
                imageSize: DicomImageSize? = nil) {
        self.filmSession = filmSession
        self.filmBox = filmBox
        self.imageSize = imageSize
    }

    public static func singleImage(label: String? = nil,
                                   imageSize: DicomImageSize? = nil) -> DicomPrintTemplate {
        DicomPrintTemplate(
            filmSession: DicomFilmSession(label: label),
            filmBox: DicomFilmBox(imageDisplayFormat: "STANDARD\\1,1"),
            imageSize: imageSize
        )
    }
}

public struct DicomImageBox: Equatable, Sendable {
    public var position: Int
    public var bitmap: DicomRenderedBitmap

    public init(position: Int = 1, bitmap: DicomRenderedBitmap) throws {
        guard position > 0 else {
            throw DicomPrintManagementError.invalidImagePosition(position)
        }
        self.position = position
        self.bitmap = bitmap
    }

    public var dataSet: DicomDataSet {
        DicomDataSet(elements: [
            printUnsigned(DicomPrintTag.imagePosition, .US, UInt(position)),
            printSequence(DicomPrintTag.basicGrayscaleImageSequence, [
                grayscaleImageDataSet
            ])
        ])
    }

    private var grayscaleImageDataSet: DicomDataSet {
        DicomDataSet(elements: [
            printUnsigned(DicomTag.samplesPerPixel.rawValue, .US, 1),
            printString(DicomTag.photometricInterpretation.rawValue, .CS, "MONOCHROME2"),
            printUnsigned(DicomTag.rows.rawValue, .US, UInt(bitmap.height)),
            printUnsigned(DicomTag.columns.rawValue, .US, UInt(bitmap.width)),
            printUnsigned(DicomTag.bitsAllocated.rawValue, .US, 8),
            printUnsigned(DicomTag.bitsStored.rawValue, .US, 8),
            printUnsigned(DicomTag.highBit.rawValue, .US, 7),
            printUnsigned(DicomTag.pixelRepresentation.rawValue, .US, 0),
            printBytes(DicomTag.pixelData.rawValue, .OB, grayscalePixelData)
        ])
    }

    private var grayscalePixelData: Data {
        var grayscale = Data()
        grayscale.reserveCapacity(bitmap.width * bitmap.height)
        let rgb = [UInt8](bitmap.rgbData)
        for offset in stride(from: 0, to: rgb.count, by: 3) {
            let red = UInt16(rgb[offset])
            let green = UInt16(rgb[offset + 1])
            let blue = UInt16(rgb[offset + 2])
            grayscale.append(UInt8((77 * red + 150 * green + 29 * blue) / 256))
        }
        return grayscale
    }
}

public struct DicomPrintJob: Equatable, Sendable {
    public var id: String
    public var filmSessionSOPInstanceUID: String
    public var filmBoxSOPInstanceUID: String
    public var filmSession: DicomFilmSession
    public var filmBox: DicomFilmBox
    public var imageBoxes: [DicomImageBox]

    public init(id: String = DicomDataSetWriter.makeUID(),
                filmSessionSOPInstanceUID: String = DicomDataSetWriter.makeUID(),
                filmBoxSOPInstanceUID: String = DicomDataSetWriter.makeUID(),
                filmSession: DicomFilmSession,
                filmBox: DicomFilmBox,
                imageBoxes: [DicomImageBox]) throws {
        guard !imageBoxes.isEmpty else {
            throw DicomPrintManagementError.emptyImageList
        }
        self.id = id
        self.filmSessionSOPInstanceUID = filmSessionSOPInstanceUID
        self.filmBoxSOPInstanceUID = filmBoxSOPInstanceUID
        self.filmSession = filmSession
        self.filmBox = filmBox
        self.imageBoxes = imageBoxes
    }

    public init(renderedBitmap: DicomRenderedBitmap,
                template: DicomPrintTemplate = .singleImage(),
                id: String = DicomDataSetWriter.makeUID()) throws {
        let imageBox = try DicomImageBox(position: 1, bitmap: renderedBitmap)
        try self.init(id: id,
                      filmSession: template.filmSession,
                      filmBox: template.filmBox,
                      imageBoxes: [imageBox])
    }

    public init(decoder: DCMDecoder,
                template: DicomPrintTemplate = .singleImage(),
                options: DicomImagePreprocessOptions = DicomImagePreprocessOptions(),
                id: String = DicomDataSetWriter.makeUID()) throws {
        let renderOptions = DicomImagePreprocessOptions(
            frameIndex: options.frameIndex,
            displaySelection: options.displaySelection,
            outputSize: template.imageSize ?? options.outputSize,
            annotations: options.annotations
        )
        let bitmap = try DicomImagePreprocessor().render(decoder: decoder, options: renderOptions)
        try self.init(renderedBitmap: bitmap, template: template, id: id)
    }

    public init(snapshotPNGData: Data,
                template: DicomPrintTemplate = .singleImage(),
                id: String = DicomDataSetWriter.makeUID()) throws {
        let bitmap = try Self.bitmap(fromPNGData: snapshotPNGData)
        try self.init(renderedBitmap: bitmap, template: template, id: id)
    }

    private static func bitmap(fromPNGData data: Data) throws -> DicomRenderedBitmap {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw DicomPrintManagementError.unsupportedSnapshotData
        }
        let width = image.width
        let height = image.height
        var rgba = [UInt8](repeating: 0, count: width * height * 4)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let didRender = rgba.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(data: buffer.baseAddress,
                                          width: width,
                                          height: height,
                                          bitsPerComponent: 8,
                                          bytesPerRow: width * 4,
                                          space: colorSpace,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
                return false
            }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard didRender else {
            throw DicomPrintManagementError.unsupportedSnapshotData
        }

        var rgb = Data()
        rgb.reserveCapacity(width * height * 3)
        for offset in stride(from: 0, to: rgba.count, by: 4) {
            rgb.append(rgba[offset])
            rgb.append(rgba[offset + 1])
            rgb.append(rgba[offset + 2])
        }
        return try DicomRenderedBitmap(width: width, height: height, rgbData: rgb)
    }
}

public struct DicomPrintJobResult: Equatable, Sendable {
    public var operation: DicomDIMSEOperationResult
    public var filmSessionSOPInstanceUID: String
    public var filmBoxSOPInstanceUID: String
    public var imageBoxSOPInstanceUIDs: [String]

    public init(operation: DicomDIMSEOperationResult,
                filmSessionSOPInstanceUID: String,
                filmBoxSOPInstanceUID: String,
                imageBoxSOPInstanceUIDs: [String]) {
        self.operation = operation
        self.filmSessionSOPInstanceUID = filmSessionSOPInstanceUID
        self.filmBoxSOPInstanceUID = filmBoxSOPInstanceUID
        self.imageBoxSOPInstanceUIDs = imageBoxSOPInstanceUIDs
    }
}

public enum DicomPrintQueueStatus: String, Codable, Equatable, Sendable {
    case queued
    case sending
    case completed
    case failed
}

public struct DicomPrintQueueEntry: Equatable, Sendable {
    public var id: String
    public var label: String?
    public var status: DicomPrintQueueStatus
    public var failureDescription: String?

    public init(id: String,
                label: String?,
                status: DicomPrintQueueStatus,
                failureDescription: String? = nil) {
        self.id = id
        self.label = label
        self.status = status
        self.failureDescription = failureDescription
    }
}

public final class DicomPrintJobQueue {
    private let lock = NSLock()
    private var order: [String] = []
    private var entriesByID: [String: DicomPrintQueueEntry] = [:]

    public init() {}

    public var entries: [DicomPrintQueueEntry] {
        lock.lock()
        defer { lock.unlock() }
        return order.compactMap { entriesByID[$0] }
    }

    @discardableResult
    public func enqueue(_ job: DicomPrintJob) -> DicomPrintQueueEntry {
        lock.lock()
        defer { lock.unlock() }
        let entry = DicomPrintQueueEntry(
            id: job.id,
            label: job.filmSession.label,
            status: .queued
        )
        if entriesByID[job.id] == nil {
            order.append(job.id)
        }
        entriesByID[job.id] = entry
        return entry
    }

    public func markSending(id: String) {
        update(id: id, status: .sending, failureDescription: nil)
    }

    public func markCompleted(id: String) {
        update(id: id, status: .completed, failureDescription: nil)
    }

    public func markFailed(id: String, failureDescription: String) {
        update(id: id, status: .failed, failureDescription: failureDescription)
    }

    private func update(id: String,
                        status: DicomPrintQueueStatus,
                        failureDescription: String?) {
        lock.lock()
        defer { lock.unlock() }
        guard var entry = entriesByID[id] else { return }
        entry.status = status
        entry.failureDescription = failureDescription
        entriesByID[id] = entry
    }
}

private func referenceDataSet(sopClassUID: String, sopInstanceUID: String) -> DicomDataSet {
    DicomDataSet(elements: [
        printString(DicomTag.referencedSOPClassUID.rawValue, .UI, sopClassUID),
        printString(DicomTag.referencedSOPInstanceUID.rawValue, .UI, sopInstanceUID)
    ])
}

private func printString(_ tag: Int, _ vr: DicomVR, _ value: String?) -> DicomDataElement {
    let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
    let dataValue: DicomDataValue
    if let trimmed, !trimmed.isEmpty {
        dataValue = .strings([trimmed])
    } else {
        dataValue = .empty
    }
    return DicomDataElement(tag: tag,
                            vr: vr,
                            value: dataValue)
}

private func printUnsigned(_ tag: Int, _ vr: DicomVR, _ value: UInt) -> DicomDataElement {
    DicomDataElement(tag: tag, vr: vr, value: .unsignedIntegers([value]))
}

private func printBytes(_ tag: Int, _ vr: DicomVR, _ value: Data) -> DicomDataElement {
    DicomDataElement(tag: tag, vr: vr, value: .bytes(value))
}

private func printSequence(_ tag: Int, _ dataSets: [DicomDataSet]) -> DicomDataElement {
    DicomDataElement(tag: tag,
                     vr: .SQ,
                     value: .sequence(dataSets.map { DicomSequenceItem(dataSet: $0) }))
}

private extension DicomDataElement {
    var isEmptyValue: Bool {
        if case .empty = value {
            return true
        }
        return false
    }
}
