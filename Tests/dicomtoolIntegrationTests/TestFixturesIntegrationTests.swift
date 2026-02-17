//
//  TestFixturesIntegrationTests.swift
//  dicomtoolIntegrationTests
//
//  Integration tests that rely on real fixture files.
//

import XCTest

final class TestFixturesIntegrationTests: XCTestCase {
    func testValidDICOMFileDiscovery() throws {
        _ = try TestFixtures.validDICOMFile()
    }
}
