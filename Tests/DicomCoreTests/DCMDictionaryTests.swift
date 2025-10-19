import XCTest
@testable import DicomCore

final class DCMDictionaryTests: XCTestCase {
    func testDictionaryLoadsFromBundle() {
        let modalityDescription = DCMDictionary.description(forKey: "00080060")
        XCTAssertNotNil(modalityDescription, "Expected DICOM tag 00080060 to exist in the dictionary")
    }
}
