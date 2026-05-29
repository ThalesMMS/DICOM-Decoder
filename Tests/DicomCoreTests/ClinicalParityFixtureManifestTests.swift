import Foundation
import XCTest

final class ClinicalParityFixtureManifestTests: XCTestCase {
    private let requiredFeatureIDs: Set<String> = [
        "uncompressed",
        "jpeg-lossless",
        "jpeg-2000",
        "rle",
        "multiframe",
        "seg",
        "rtstruct",
        "rtdose",
        "sr-tid1500",
        "pr",
        "hp",
        "rwv",
        "pmap",
        "dicomdir",
        "encapsulated-pdf",
        "waveform",
        "video"
    ]

    private let requiredGoldenCategories: Set<String> = [
        "metadata",
        "pixel-hash",
        "frame-count",
        "geometry",
        "sr-tree",
        "segment-metadata"
    ]

    func testManifestCoversRequiredClinicalParityFixtures() throws {
        let manifestURL = repoRoot().appendingPathComponent("Roadmap/ClinicalParityFixtureManifest.json")
        let manifest = try JSONDecoder().decode(
            ClinicalParityFixtureManifest.self,
            from: Data(contentsOf: manifestURL)
        )

        XCTAssertEqual(manifest.version, 1)
        XCTAssertFalse(manifest.policy.storage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        XCTAssertFalse(manifest.policy.privacy.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        XCTAssertFalse(manifest.policy.ci.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

        let ids = manifest.features.map(\.id)
        XCTAssertEqual(Set(ids), requiredFeatureIDs)
        XCTAssertEqual(ids.count, requiredFeatureIDs.count)

        for feature in manifest.features {
            XCTAssertFalse(feature.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, feature.id)
            XCTAssertFalse(feature.representation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, feature.id)
            XCTAssertFalse(feature.artifact.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, feature.id)
            XCTAssertFalse(feature.synthesis.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, feature.id)
            XCTAssertFalse(feature.issues.isEmpty, feature.id)
            XCTAssertFalse(feature.goldens.isEmpty, feature.id)
            XCTAssertFalse(feature.tests.isEmpty, feature.id)
            XCTAssertFalse(feature.ci.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, feature.id)

            for issue in feature.issues {
                XCTAssertTrue(issue.range(of: #"^#[0-9]+$"#, options: .regularExpression) != nil,
                              "Invalid issue reference for \(feature.id): \(issue)")
            }
            for golden in feature.goldens {
                XCTAssertFalse(golden.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, feature.id)
            }
            assertRepoPathExists(feature.artifact, featureID: feature.id)
            for testPath in feature.tests {
                assertRepoPathExists(testPath, featureID: feature.id)
            }
        }

        let coveredGoldenCategories = Set(manifest.features.flatMap(\.goldens))
        XCTAssertTrue(requiredGoldenCategories.isSubset(of: coveredGoldenCategories),
                      "Manifest must cover QA-02 golden categories: \(requiredGoldenCategories.subtracting(coveredGoldenCategories).sorted())")
    }

    func testDoneMatrixFeaturesAreBoundToIssuesAndGoldenTests() throws {
        let manifestURL = repoRoot().appendingPathComponent("Roadmap/ClinicalParityFixtureManifest.json")
        let matrixURL = repoRoot().appendingPathComponent("Roadmap/DICOMAdvancedParityMatrix.md")
        let manifest = try JSONDecoder().decode(
            ClinicalParityFixtureManifest.self,
            from: Data(contentsOf: manifestURL)
        )
        let matrixText = try String(contentsOf: matrixURL, encoding: .utf8)
        let doneIssues = Set(matrixText
            .split(separator: "\n")
            .filter { $0.contains("| Done") || $0.contains("| Done:") }
            .compactMap { row -> String? in
                guard let range = row.range(of: #"#\d+"#, options: .regularExpression) else {
                    return nil
                }
                return String(row[range])
            })

        for feature in manifest.features {
            let doneFeatureIssues = feature.issues.filter(doneIssues.contains)
            guard !doneFeatureIssues.isEmpty else {
                continue
            }
            XCTAssertFalse(feature.tests.isEmpty, "\(feature.id) must keep CI-visible tests while \(doneFeatureIssues) is marked done")
            XCTAssertFalse(feature.goldens.isEmpty, "\(feature.id) must keep golden expectations while \(doneFeatureIssues) is marked done")
        }
    }

    func testManifestDoesNotExposePrivateDataOrLocalPaths() throws {
        let manifestURL = repoRoot().appendingPathComponent("Roadmap/ClinicalParityFixtureManifest.json")
        let manifestText = try String(contentsOf: manifestURL, encoding: .utf8)
        let blockedMarkers = [
            "/" + "Users" + "/",
            ["DICOM", "Example"].joined(separator: "_"),
            "Demo" + "^",
            ["D", "OE"].joined()
        ]

        for marker in blockedMarkers {
            XCTAssertFalse(manifestText.contains(marker), "Manifest contains blocked marker: \(marker)")
        }
    }

    private func assertRepoPathExists(_ path: String, featureID: String) {
        let url = repoRoot().appendingPathComponent(path)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path),
                      "Missing manifest path for \(featureID): \(path)")
    }

    private func repoRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}

private struct ClinicalParityFixtureManifest: Decodable {
    var version: Int
    var policy: ClinicalParityFixtureManifestPolicy
    var features: [ClinicalParityFixtureManifestFeature]
}

private struct ClinicalParityFixtureManifestPolicy: Decodable {
    var storage: String
    var privacy: String
    var ci: String
}

private struct ClinicalParityFixtureManifestFeature: Decodable {
    var id: String
    var label: String
    var issues: [String]
    var goldens: [String]
    var representation: String
    var artifact: String
    var synthesis: String
    var tests: [String]
    var ci: String
}
