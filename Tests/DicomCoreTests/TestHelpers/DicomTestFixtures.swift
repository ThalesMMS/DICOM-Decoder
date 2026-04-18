import Foundation
import XCTest

/// Computes the URL for the `Fixtures` directory used by tests, located relative to this source file.
/// - Returns: A `URL` pointing to the `Fixtures` directory.
func getFixturesPath() -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Fixtures", isDirectory: true)
}

/// Locate the CT synthetic DICOM fixture and return its file URL.
/// - Returns: The `URL` of the CT synthetic DICOM fixture file (`CT/ct_synthetic.dcm`).
/// - Throws: `XCTSkip` if the fixtures directory or the CT synthetic fixture is missing.
func getCTSyntheticFixtureURL() throws -> URL {
    try requireFixtureURL(relativePath: "CT/ct_synthetic.dcm")
}

/// Locate the MR synthetic DICOM fixture URL.
/// - Returns: The file URL for "MR/mr_synthetic.dcm" inside the test Fixtures directory.
/// - Throws: `XCTSkip` when the fixture file or the Fixtures directory is missing.
func getMRSyntheticFixtureURL() throws -> URL {
    try requireFixtureURL(relativePath: "MR/mr_synthetic.dcm")
}

/// Locate and return the file URL for the US synthetic DICOM fixture.
/// - Returns: The file URL for "US/us_synthetic.dcm".
/// - Throws: `XCTSkip` if the fixtures directory or the specified fixture file is missing.
func getUSSyntheticFixtureURL() throws -> URL {
    try requireFixtureURL(relativePath: "US/us_synthetic.dcm")
}

/// Locate the XR synthetic DICOM fixture.
/// - Returns: The filesystem URL to the "XR/xr_synthetic.dcm" file inside the Fixtures directory.
/// - Throws: `XCTSkip` if the Fixtures directory or the specified XR fixture file is missing.
func getXRSyntheticFixtureURL() throws -> URL {
    try requireFixtureURL(relativePath: "XR/xr_synthetic.dcm")
}

/// Finds and returns the first DICOM file URL inside the project's Fixtures directory.
/// 
/// Searches the Fixtures directory for a file whose extension is `dcm` or `dicom` and returns its URL.
/// - Returns: The file URL of the first DICOM file found.
/// - Throws: `XCTSkip` if the Fixtures directory does not exist or if no DICOM files are found.
func getAnyFixtureDICOMURL() throws -> URL {
    let fixturesPath = getFixturesPath()

    guard FileManager.default.fileExists(atPath: fixturesPath.path) else {
        throw XCTSkip("Fixtures directory not found. See Tests/DicomCoreTests/Fixtures/README.md for setup instructions.")
    }

    let enumerator = FileManager.default.enumerator(at: fixturesPath, includingPropertiesForKeys: nil)
    var candidates: [URL] = []
    while let fileURL = enumerator?.nextObject() as? URL {
        let ext = fileURL.pathExtension.lowercased()
        if ext == "dcm" || ext == "dicom" {
            candidates.append(fileURL)
        }
    }

    if let first = candidates.sorted(by: { $0.path < $1.path }).first {
        return first
    }

    throw XCTSkip("No DICOM files found in Fixtures. See Tests/DicomCoreTests/Fixtures/README.md for setup instructions.")
}

/// Resolve the URL for a file located under the test Fixtures directory or skip the test if it is missing.
/// - Parameters:
///   - relativePath: Path to the fixture file relative to the Fixtures directory (e.g. "CT/ct_synthetic.dcm").
/// - Returns: The file `URL` for the requested fixture.
/// - Throws: `XCTSkip` when the fixture file cannot be found; message includes setup instructions.
private func requireFixtureURL(relativePath: String) throws -> URL {
    let url = getFixturesPath().appendingPathComponent(relativePath)
    guard FileManager.default.fileExists(atPath: url.path) else {
        throw XCTSkip("Fixture '\(relativePath)' not found. See Tests/DicomCoreTests/Fixtures/README.md for setup instructions.")
    }
    return url
}
