//
//  DicomAnonymizer.swift
//  DicomCore
//
//  Safe Part 10 rewrite and anonymization (issue #1236): a policy-driven
//  engine that removes, replaces, keeps, and remaps elements; traverses
//  nested sequences; preserves the transfer syntax and file meta
//  consistency on write; carries encapsulated Pixel Data byte-for-byte
//  (Basic/Extended Offset Tables included, since the fragment layout is
//  untouched); remaps UIDs deterministically so study/series/instance
//  relationships stay consistent; and emits an audit that never records
//  original PHI values.
//

import Foundation

/// Per-tag rewrite policy.
public struct DicomRewritePolicy: Sendable {
    public enum Action: Equatable, Sendable {
        /// Keep the element untouched.
        case keep
        /// Delete the element.
        case remove
        /// Replace the value with a fixed replacement string.
        case replace(String)
        /// Deterministically remap the UID value (relationships preserved).
        case remapUID
    }

    /// Explicit per-tag actions (applied at every nesting level).
    public var actions: [Int: Action]

    /// Remove private elements (odd group numbers), including creators.
    public var removePrivateTags: Bool

    /// Root prefix for remapped UIDs.
    ///
    /// Remapped UIDs are `"\(uidRoot).\(first).\(second)"` with two
    /// `UInt64` components of up to 20 decimal digits each, so the root
    /// must fit `maximumUIDRootLength` to keep every output inside the
    /// DICOM 64-character UI limit. Length is the only validated
    /// property; supplying a well-formed UID prefix (digits and dots)
    /// remains the caller's responsibility.
    public var uidRoot: String

    /// Longest `uidRoot` that keeps remapped UIDs within the DICOM
    /// 64-character maximum: 64 − 2 separators − 2 × 20-digit components.
    public static let maximumUIDRootLength = 22

    public init(actions: [Int: Action], removePrivateTags: Bool, uidRoot: String = "2.25") {
        self.actions = actions
        self.removePrivateTags = removePrivateTags
        self.uidRoot = uidRoot
    }

    /// Baseline de-identification: identity fields replaced or removed,
    /// study/series/instance/frame-of-reference and referenced SOP UIDs
    /// remapped, private tags removed.
    ///
    /// This baseline is NOT the complete PS3.15 Basic De-identification
    /// Profile. Referenced Study Sequence (0008,1110) and Referenced
    /// Series Sequence (0008,1115) are retained, with their linkage UIDs
    /// de-identified by the recursive Referenced SOP Instance UID
    /// (0008,1155) remap. Notable categories the baseline does NOT
    /// cover: dates and times beyond the birth date, operator and
    /// physician names beyond the referring physician, free-text
    /// description/comment fields, and the institution address. Callers
    /// needing full profile conformance must extend the actions.
    public static let defaultAnonymization = DicomRewritePolicy(
        actions: [
            DicomTag.patientName.rawValue: .replace("ANONYMIZED"),
            DicomTag.patientID.rawValue: .replace("ANON"),
            0x0010_0030: .remove, // Patient Birth Date
            0x0010_1001: .remove, // Other Patient Names
            0x0010_1040: .remove, // Patient Address
            0x0010_2154: .remove, // Patient Telephone Numbers
            0x0008_0050: .replace(""), // Accession Number (type 2)
            DicomTag.studyID.rawValue: .replace(""), // Study ID (type 2)
            0x0008_1010: .remove, // Station Name
            0x0018_1000: .remove, // Device Serial Number
            0x0040_1001: .remove, // Requested Procedure ID
            DicomTag.referringPhysicianName.rawValue: .remove,
            DicomTag.institutionName.rawValue: .remove,
            DicomTag.studyInstanceUID.rawValue: .remapUID,
            DicomTag.seriesInstanceUID.rawValue: .remapUID,
            DicomTag.sopInstanceUID.rawValue: .remapUID,
            DicomTag.frameOfReferenceUID.rawValue: .remapUID,
            DicomTag.referencedSOPInstanceUID.rawValue: .remapUID
        ],
        removePrivateTags: true
    )
}

/// Policy misconfiguration detected before any rewrite output is produced.
public enum DicomRewritePolicyError: Error, Equatable, LocalizedError, Sendable {
    /// The UID root would push remapped UIDs past the DICOM 64-character
    /// maximum.
    case uidRootTooLong(root: String, maximumLength: Int)

    public var errorDescription: String? {
        switch self {
        case .uidRootTooLong(let root, let maximumLength):
            return "The UID root '\(root)' (\(root.count) characters) exceeds the "
                + "\(maximumLength)-character budget that keeps remapped UIDs within "
                + "the DICOM 64-character maximum."
        }
    }
}

/// One audited rewrite decision. Notes never carry original PHI values.
public struct DicomRewriteAuditEntry: Equatable, Sendable {
    public enum Disposition: String, Equatable, Sendable {
        case changed
        case removed
        case kept
        case blocked
        case unsupported
        case remapped
    }

    /// Element path, for example `(0010,0010)` or `(0008,1140)[0]/(0008,1155)`.
    public let path: String
    public let tag: Int
    public let disposition: Disposition
    public let note: String?

    public init(path: String, tag: Int, disposition: Disposition, note: String? = nil) {
        self.path = path
        self.tag = tag
        self.disposition = disposition
        self.note = note
    }
}

/// Result of one safe rewrite operation.
public struct DicomRewriteResult: Sendable {
    /// The rewritten Part 10 file bytes.
    public let fileData: Data
    /// The rewritten dataset (pixel data bytes included).
    public let dataSet: DicomDataSet
    /// Audit of every policy decision.
    public let audit: [DicomRewriteAuditEntry]
    /// Deterministic original-UID to remapped-UID mapping.
    public let uidMap: [String: String]
}

/// Safe Part 10 rewrite / anonymization engine.
public struct DicomAnonymizer {
    /// Pixel-structure tags the policy is never allowed to alter.
    static let structuralTags: Set<Int> = [
        DicomTag.sopClassUID.rawValue,
        DicomTag.rows.rawValue,
        DicomTag.columns.rawValue,
        DicomTag.bitsAllocated.rawValue,
        DicomTag.bitsStored.rawValue,
        DicomTag.highBit.rawValue,
        DicomTag.pixelRepresentation.rawValue,
        DicomTag.samplesPerPixel.rawValue,
        DicomTag.photometricInterpretation.rawValue,
        DicomTag.numberOfFrames.rawValue,
        DicomTag.pixelData.rawValue
    ]

    public let policy: DicomRewritePolicy

    public init(policy: DicomRewritePolicy = .defaultAnonymization) {
        self.policy = policy
    }

    /// Rewrites a Part 10 file on disk.
    public func rewrite(contentsOf url: URL) throws -> DicomRewriteResult {
        let decoder = try DCMDecoder(contentsOf: url)
        return try rewrite(decoder: decoder)
    }

    /// Rewrites in-memory Part 10 bytes.
    public func rewrite(_ data: Data) throws -> DicomRewriteResult {
        let decoder = try DCMDecoder(data: data)
        return try rewrite(decoder: decoder)
    }

    func rewrite(decoder: DCMDecoder) throws -> DicomRewriteResult {
        guard policy.uidRoot.count <= DicomRewritePolicy.maximumUIDRootLength else {
            throw DicomRewritePolicyError.uidRootTooLong(
                root: policy.uidRoot,
                maximumLength: DicomRewritePolicy.maximumUIDRootLength
            )
        }
        let source = Self.datasetCarryingPixelBytes(from: decoder)

        var state = RewriteState(policy: policy)
        let rewritten = rewriteDataSet(source, path: "", state: &state)

        let transferSyntax = DicomTransferSyntax(uid: decoder.info(for: .transferSyntaxUID))
            ?? .explicitVRLittleEndian
        let sopClassUID = decoder.info(for: .sopClassUID)
        let outputSOPInstanceUID = rewritten.string(for: .sopInstanceUID)
            ?? decoder.info(for: .sopInstanceUID)

        let fileData = try DicomDataSetWriter.part10Data(
            from: rewritten,
            options: DicomPart10WriterOptions(
                transferSyntax: transferSyntax,
                mediaStorageSOPClassUID: sopClassUID.isEmpty ? nil : sopClassUID,
                mediaStorageSOPInstanceUID: outputSOPInstanceUID
            )
        )
        return DicomRewriteResult(
            fileData: fileData,
            dataSet: rewritten,
            audit: state.audit,
            uidMap: state.uidMap
        )
    }

    // MARK: - Recursive policy application

    private struct RewriteState {
        let policy: DicomRewritePolicy
        var audit: [DicomRewriteAuditEntry] = []
        var uidMap: [String: String] = [:]

        init(policy: DicomRewritePolicy) {
            self.policy = policy
        }

        mutating func remappedUID(for original: String) -> String {
            if let existing = uidMap[original] {
                return existing
            }
            let remapped = DicomAnonymizer.deterministicUID(for: original, root: policy.uidRoot)
            uidMap[original] = remapped
            return remapped
        }
    }

    private func rewriteDataSet(_ dataSet: DicomDataSet, path: String, state: inout RewriteState) -> DicomDataSet {
        var output = DicomDataSet()
        for element in dataSet.elements {
            // File meta (group 0002) and group-length elements are owned by
            // the writer; never copy them into the output dataset body.
            let group = element.tag >> 16
            if group == 0x0002 || (element.tag & 0xFFFF) == 0 {
                continue
            }

            let elementPath = path + Self.tagPathComponent(element.tag)

            if state.policy.removePrivateTags, group % 2 == 1 {
                state.audit.append(DicomRewriteAuditEntry(
                    path: elementPath, tag: element.tag, disposition: .removed, note: "private element"
                ))
                continue
            }

            let action = state.policy.actions[element.tag] ?? .keep

            if Self.structuralTags.contains(element.tag), action != .keep {
                state.audit.append(DicomRewriteAuditEntry(
                    path: elementPath, tag: element.tag, disposition: .blocked,
                    note: "structural element; the policy action was not applied"
                ))
                output.set(element)
                continue
            }

            switch action {
            case .keep:
                if case .sequence(let items) = element.value {
                    var rewrittenItems = [DicomSequenceItem]()
                    for (index, item) in items.enumerated() {
                        let itemPath = elementPath + "[\(index)]/"
                        rewrittenItems.append(DicomSequenceItem(
                            dataSet: rewriteDataSet(item.dataSet, path: itemPath, state: &state)
                        ))
                    }
                    output.set(DicomDataElement(
                        tag: element.tag, vr: element.vr, value: .sequence(rewrittenItems), name: element.name
                    ))
                } else {
                    output.set(element)
                }

            case .remove:
                state.audit.append(DicomRewriteAuditEntry(
                    path: elementPath, tag: element.tag, disposition: .removed
                ))

            case .replace(let replacement):
                if case .sequence = element.value {
                    state.audit.append(DicomRewriteAuditEntry(
                        path: elementPath, tag: element.tag, disposition: .unsupported,
                        note: "replace is not defined for sequences; element kept"
                    ))
                    output.set(element)
                } else {
                    output.set(DicomDataElement(
                        tag: element.tag,
                        vr: element.vr,
                        value: replacement.isEmpty ? .empty : .strings([replacement]),
                        name: element.name
                    ))
                    state.audit.append(DicomRewriteAuditEntry(
                        path: elementPath, tag: element.tag, disposition: .changed,
                        note: "replaced with policy value"
                    ))
                }

            case .remapUID:
                let originals = element.stringValues
                guard !originals.isEmpty else {
                    state.audit.append(DicomRewriteAuditEntry(
                        path: elementPath, tag: element.tag, disposition: .unsupported,
                        note: "remapUID requires a UI string value; element kept"
                    ))
                    output.set(element)
                    continue
                }
                let remapped = originals.map { state.remappedUID(for: $0) }
                output.set(DicomDataElement(
                    tag: element.tag, vr: element.vr, value: .strings(remapped), name: element.name
                ))
                state.audit.append(DicomRewriteAuditEntry(
                    path: elementPath, tag: element.tag, disposition: .remapped,
                    note: "uid remapped deterministically"
                ))
            }
        }
        return output
    }

    // MARK: - Helpers

    /// Deterministic replacement UID: stable for the same input across
    /// operations, so cross-file study/series relationships also hold.
    static func deterministicUID(for original: String, root: String) -> String {
        var first: UInt64 = 0xcbf29ce484222325
        for byte in original.utf8 {
            first ^= UInt64(byte)
            first = first &* 0x100000001b3
        }
        var second: UInt64 = 0x9e3779b97f4a7c15
        for byte in original.utf8 {
            second = (second &* 31) &+ UInt64(byte)
        }
        return "\(root).\(first).\(second)"
    }

    /// The decoder's dataset with Pixel Data carried byte-for-byte:
    /// encapsulated payloads copy the raw item-structured region (Basic
    /// Offset Table, fragments, and delimiter) for the writer's
    /// pass-through; native values copy their raw bytes.
    static func datasetCarryingPixelBytes(from decoder: DCMDecoder) -> DicomDataSet {
        var source = decoder.dataSet
        if decoder.compressedImage,
           let encapsulated = rawEncapsulatedPixelDataRegion(from: decoder) {
            source.set(DicomDataElement(tag: DicomTag.pixelData.rawValue, vr: .OB, value: .bytes(encapsulated)))
        } else if let descriptor = decoder.pixelDataDescriptor {
            let fileData = decoder.dicomDataSnapshot()
            let end = descriptor.pixelDataOffset + descriptor.totalPixelBytes
            if descriptor.pixelDataOffset >= 0, end <= fileData.count {
                source.set(DicomDataElement(
                    tag: DicomTag.pixelData.rawValue,
                    vr: descriptor.bitsAllocated > 8 ? .OW : .OB,
                    value: .bytes(Data(fileData[descriptor.pixelDataOffset..<end]))
                ))
            }
        }
        return source
    }

    /// Extracts the raw encapsulated Pixel Data value region (Basic Offset
    /// Table item through the sequence delimiter) for byte-exact copying.
    static func rawEncapsulatedPixelDataRegion(from decoder: DCMDecoder) -> Data? {
        guard let descriptor = decoder.encapsulatedPixelDataDescriptor else {
            return nil
        }
        let fileData = decoder.dicomDataSnapshot()
        let start = decoder.offset
        guard start >= 0, start < fileData.count else { return nil }

        // The region ends after the sequence delimiter that follows the
        // last fragment (or the offset table when there are none).
        var scan = descriptor.fragments.map(\.itemRange.upperBound).max() ?? start
        while scan + 8 <= fileData.count {
            if fileData[scan] == 0xFE, fileData[scan + 1] == 0xFF,
               fileData[scan + 2] == 0xDD, fileData[scan + 3] == 0xE0 {
                return Data(fileData[start..<(scan + 8)])
            }
            scan += 1
        }
        return nil
    }

    private static func tagPathComponent(_ tag: Int) -> String {
        String(format: "(%04X,%04X)", (tag >> 16) & 0xFFFF, tag & 0xFFFF)
    }
}
