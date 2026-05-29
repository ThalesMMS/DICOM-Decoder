import Foundation
import XCTest
@testable import DicomCore

final class DicomPrintManagementTests: XCTestCase {
    func testRenderedBitmapBuildsGrayscaleImageBoxDataSet() throws {
        let bitmap = try DicomRenderedBitmap(
            width: 2,
            height: 1,
            rgbData: Data([0, 0, 0, 255, 255, 255])
        )

        let job = try DicomPrintJob(
            renderedBitmap: bitmap,
            template: .singleImage(label: "PRINT-1"),
            id: "job-1"
        )

        XCTAssertEqual(job.filmSession.label, "PRINT-1")
        XCTAssertEqual(job.imageBoxes.count, 1)
        let imageBoxDataSet = job.imageBoxes[0].dataSet
        XCTAssertEqual(imageBoxDataSet.int(for: DicomPrintTag.imagePosition), 1)
        let imageDataSet = imageBoxDataSet
            .sequenceItems(for: DicomPrintTag.basicGrayscaleImageSequence)
            .first?.dataSet
        XCTAssertEqual(imageDataSet?.int(for: .rows), 1)
        XCTAssertEqual(imageDataSet?.int(for: .columns), 2)
        XCTAssertEqual(imageDataSet?.string(for: .photometricInterpretation), "MONOCHROME2")
        XCTAssertEqual(imageDataSet?.element(for: .pixelData)?.bytesValue, Data([0, 255]))
    }

    func testPrintQueueTracksStatusAndFailureReason() throws {
        let bitmap = try DicomRenderedBitmap(width: 1,
                                             height: 1,
                                             rgbData: Data([128, 128, 128]))
        let job = try DicomPrintJob(renderedBitmap: bitmap,
                                    template: .singleImage(label: "QUEUE"),
                                    id: "queue-job")
        let queue = DicomPrintJobQueue()

        let queued = queue.enqueue(job)
        XCTAssertEqual(queued.status, .queued)
        XCTAssertEqual(queue.entries, [queued])

        queue.markSending(id: job.id)
        XCTAssertEqual(queue.entries.first?.status, .sending)

        queue.markFailed(id: job.id, failureDescription: "Printer rejected film box")
        XCTAssertEqual(queue.entries.first?.status, .failed)
        XCTAssertEqual(queue.entries.first?.failureDescription, "Printer rejected film box")

        queue.markCompleted(id: job.id)
        XCTAssertEqual(queue.entries.first?.status, .completed)
        XCTAssertNil(queue.entries.first?.failureDescription)
    }
}
