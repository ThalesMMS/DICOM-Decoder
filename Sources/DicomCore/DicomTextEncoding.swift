import Foundation

public struct DicomSpecificCharacterSet: Equatable, Hashable, Sendable {
    public let definedTerms: [String]

    public static let defaultCharacterSet = DicomSpecificCharacterSet(definedTerms: ["ISO_IR 6"])

    public init(_ rawValue: String?) {
        let terms = rawValue?
            .components(separatedBy: "\\")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "\0"))) }
            .filter { !$0.isEmpty } ?? []
        self.init(definedTerms: terms)
    }

    public init(definedTerms: [String]) {
        let terms = definedTerms
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "\0"))) }
            .filter { !$0.isEmpty }
        self.definedTerms = terms.isEmpty ? ["ISO_IR 6"] : terms
    }

    public var usesISO2022: Bool {
        normalizedTerms.contains { $0.hasPrefix("ISO 2022") }
    }

    internal func decode(_ data: Data) -> String {
        guard !data.isEmpty else { return "" }
        for encoding in decodingCandidates {
            if let value = String(data: data, encoding: encoding) {
                return normalize(value)
            }
        }
        return normalize(String(decoding: data, as: UTF8.self))
    }

    internal func encode(_ value: String) -> Data {
        value.data(using: primaryEncoding) ?? Data(value.utf8)
    }

    private var normalizedTerms: [String] {
        definedTerms.map { $0.uppercased() }
    }

    private var primaryEncoding: String.Encoding {
        let terms = normalizedTerms

        if terms.contains("ISO_IR 192") {
            return .utf8
        }
        if terms.contains("GB18030") || terms.contains("GBK") {
            return Self.coreFoundationEncoding(.GB_18030_2000)
        }
        if terms.contains("ISO_IR 100") {
            return .isoLatin1
        }
        if terms.contains("ISO_IR 101") {
            return .isoLatin2
        }
        if terms.contains("ISO_IR 109") {
            return Self.coreFoundationEncoding(.isoLatin3)
        }
        if terms.contains("ISO_IR 110") {
            return Self.coreFoundationEncoding(.isoLatin4)
        }
        if terms.contains("ISO_IR 144") {
            return Self.coreFoundationEncoding(.isoLatinCyrillic)
        }
        if terms.contains("ISO_IR 127") {
            return Self.coreFoundationEncoding(.isoLatinArabic)
        }
        if terms.contains("ISO_IR 126") {
            return Self.coreFoundationEncoding(.isoLatinGreek)
        }
        if terms.contains("ISO_IR 138") {
            return Self.coreFoundationEncoding(.isoLatinHebrew)
        }
        if terms.contains("ISO_IR 148") {
            return Self.coreFoundationEncoding(.isoLatin5)
        }
        if terms.contains("ISO_IR 166") {
            return Self.coreFoundationEncoding(.isoLatinThai)
        }
        if terms.contains(where: { $0 == "ISO 2022 IR 13" || $0 == "ISO 2022 IR 87" || $0 == "ISO 2022 IR 159" }) {
            return .iso2022JP
        }
        if terms.contains("ISO_IR 13") {
            return .shiftJIS
        }
        return .utf8
    }

    private static func coreFoundationEncoding(_ encoding: CFStringEncodings) -> String.Encoding {
        String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(encoding.rawValue)))
    }

    private var decodingCandidates: [String.Encoding] {
        let candidates = [primaryEncoding, .utf8, .isoLatin1]
        var seen = Set<UInt>()
        return candidates.filter { seen.insert($0.rawValue).inserted }
    }

    private func normalize(_ value: String) -> String {
        var string = value
        if let nullIndex = string.firstIndex(of: "\0") {
            string = String(string[..<nullIndex])
        }
        return string
            .trimmingCharacters(in: .whitespaces)
            .precomposedStringWithCanonicalMapping
    }
}

public enum DicomTextSanitizer {
    public static func sanitizedForDisplay(_ value: String) -> String {
        var result = String.UnicodeScalarView()
        var lastInsertedSpace = false

        for scalar in value.unicodeScalars {
            if scalar.value == 0 ||
                (0x0001...0x001F).contains(scalar.value) ||
                (0x007F...0x009F).contains(scalar.value) {
                if !lastInsertedSpace {
                    result.append(" ")
                    lastInsertedSpace = true
                }
            } else {
                result.append(scalar)
                lastInsertedSpace = scalar == " "
            }
        }

        return String(result)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .precomposedStringWithCanonicalMapping
    }
}

public extension DicomDataElement {
    var sanitizedStringValue: String? {
        stringValue.map(DicomTextSanitizer.sanitizedForDisplay)
    }

    var sanitizedStringValues: [String] {
        stringValues.map(DicomTextSanitizer.sanitizedForDisplay)
    }
}

public extension DicomDataSet {
    func sanitizedString(for tag: Int) -> String? {
        element(for: tag)?.sanitizedStringValue
    }

    func sanitizedString(for tag: DicomTag) -> String? {
        sanitizedString(for: tag.rawValue)
    }

    func sanitizedStrings(for tag: Int) -> [String] {
        element(for: tag)?.sanitizedStringValues ?? []
    }

    func sanitizedStrings(for tag: DicomTag) -> [String] {
        sanitizedStrings(for: tag.rawValue)
    }
}
