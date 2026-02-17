//
//  TestFixtures.swift
//  dicomtoolTests
//
//  Shared helpers for locating test DICOM fixtures.
//

import Foundation
import XCTest

enum TestFixtures {
    static func fixturesPath() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("DicomCoreTests")
            .appendingPathComponent("Fixtures")
    }

    static func validDICOMFile() throws -> URL {
        let fixturesPath = fixturesPath()

        guard FileManager.default.fileExists(atPath: fixturesPath.path) else {
            throw XCTSkip("Fixtures directory not found. See Tests/DicomCoreTests/Fixtures/README.md for setup instructions.")
        }

        let ctFile = fixturesPath.appendingPathComponent("CT").appendingPathComponent("ct_synthetic.dcm")
        if FileManager.default.fileExists(atPath: ctFile.path) {
            return ctFile
        }

        let enumerator = FileManager.default.enumerator(at: fixturesPath, includingPropertiesForKeys: nil)
        while let fileURL = enumerator?.nextObject() as? URL {
            let ext = fileURL.pathExtension.lowercased()
            if ext == "dcm" || ext == "dicom" {
                return fileURL
            }
        }

        throw XCTSkip("No DICOM files found in Fixtures. See Tests/DicomCoreTests/Fixtures/README.md for setup instructions.")
    }
}
