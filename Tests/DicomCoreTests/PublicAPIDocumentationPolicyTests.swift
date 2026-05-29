import Foundation
import XCTest

final class PublicAPIDocumentationPolicyTests: XCTestCase {
    func testDocumentationManifestPointsToExistingPolicyGateAndDocs() throws {
        let manifest = try loadManifest()

        XCTAssertEqual(manifest.issue, 283)
        assertRepoPathExists(manifest.policy)
        assertRepoPathExists(manifest.gate.script)
        XCTAssertFalse(manifest.ownerDocumentation.isEmpty)

        for owner in manifest.ownerDocumentation {
            XCTAssertFalse(owner.owner.isEmpty)
            XCTAssertFalse(owner.apiDocumentation.isEmpty, owner.owner)
            XCTAssertFalse(owner.usageDocumentation.isEmpty, owner.owner)
            XCTAssertFalse(owner.limitations.isEmpty, owner.owner)
            for path in owner.apiDocumentation + owner.usageDocumentation {
                assertRepoPathExists(path)
            }
            for limitation in owner.limitations {
                XCTAssertFalse(limitation.category.isEmpty, owner.owner)
                assertRepoPathExists(limitation.path)
            }
        }

        let limitationCategories = Set(manifest.ownerDocumentation.flatMap { owner in
            owner.limitations.map(\.category)
        })
        XCTAssertTrue(limitationCategories.isSuperset(of: [
            "codecs",
            "network",
            "clinicalObjects",
            "rendering",
            "fixtures",
            "device"
        ]))
    }

    func testDemoWorkflowsAreDocumentedInDemoReadme() throws {
        let manifest = try loadManifest()

        XCTAssertGreaterThanOrEqual(manifest.demoWorkflows.count, 4)
        for workflow in manifest.demoWorkflows {
            let document = try String(contentsOf: repoRoot.appendingPathComponent(workflow.path), encoding: .utf8)
            XCTAssertTrue(document.contains(workflow.visibleFlow),
                          "\(workflow.path) should mention \(workflow.visibleFlow)")
        }
    }

    func testMatrixMarksDocumentationGateDoneOnlyWithManifestAndTests() throws {
        let manifest = try loadManifest()
        let matrix = try String(contentsOf: repoRoot.appendingPathComponent("Roadmap/DICOMAdvancedParityMatrix.md"),
                                encoding: .utf8)
        let row = try XCTUnwrap(matrix
            .split(separator: "\n")
            .first { $0.contains("| #283 |") })

        XCTAssertTrue(row.contains("| Done:"), String(row))
        XCTAssertTrue(row.contains("documentation manifest"), String(row))
        for testPath in manifest.tests {
            assertRepoPathExists(testPath)
        }
    }

    private func loadManifest() throws -> PublicAPIDocumentationManifest {
        let url = repoRoot.appendingPathComponent("Roadmap/PublicAPIDocumentationManifest.json")
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(PublicAPIDocumentationManifest.self, from: data)
    }

    private func assertRepoPathExists(_ path: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(FileManager.default.fileExists(atPath: repoRoot.appendingPathComponent(path).path),
                      "Missing documentation path: \(path)",
                      file: file,
                      line: line)
    }

    private var repoRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}

private struct PublicAPIDocumentationManifest: Decodable {
    var issue: Int
    var policy: String
    var gate: PublicAPIDocumentationGate
    var ownerDocumentation: [PublicAPIDocumentationOwner]
    var demoWorkflows: [PublicAPIDocumentationDemoWorkflow]
    var tests: [String]
}

private struct PublicAPIDocumentationGate: Decodable {
    var script: String
}

private struct PublicAPIDocumentationOwner: Decodable {
    var owner: String
    var apiDocumentation: [String]
    var usageDocumentation: [String]
    var limitations: [PublicAPIDocumentationLimitation]
}

private struct PublicAPIDocumentationLimitation: Decodable {
    var category: String
    var path: String
}

private struct PublicAPIDocumentationDemoWorkflow: Decodable {
    var id: String
    var path: String
    var visibleFlow: String
}
