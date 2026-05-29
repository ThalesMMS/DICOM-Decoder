//
//  PerformanceBudgetTests.swift
//  DicomCore
//
//  Tests for the clinical performance budget manifest and gate logic.
//

import XCTest
@testable import DicomCore

final class PerformanceBudgetTests: XCTestCase {
    func testManifestCoversIssue282RequiredStagesAndBuildConfigurations() throws {
        let manifest = try PerformanceBudgetManifestLoader.loadRepositoryManifest()

        XCTAssertEqual(manifest.issue, 282)
        XCTAssertEqual(Set(manifest.requiredStages), Set(PerformanceBudgetStage.allCases))
        XCTAssertEqual(Set(manifest.buildConfigurations), Set(PerformanceBudgetBuildConfiguration.allCases))
        XCTAssertGreaterThan(manifest.warningRatio, 0)
        XCTAssertLessThan(manifest.warningRatio, 1)

        let allBudgetStages = Set(manifest.scenarios.flatMap { scenario in
            scenario.budgets.map(\.stage)
        })
        for stage in manifest.requiredStages {
            XCTAssertTrue(allBudgetStages.contains(stage), "Missing budget for \(stage.rawValue)")
        }

        let requiredEnvironmentFields: Set<String> = [
            "deviceName",
            "osVersion",
            "architecture",
            "modelIdentifier",
            "buildConfiguration",
            "benchmarkMode",
            "fixtureID"
        ]
        XCTAssertEqual(Set(manifest.comparisonProfile.requiredResultEnvironmentFields),
                       requiredEnvironmentFields)
    }

    func testManifestUsesSmallRepresentativeLocalFixtures() throws {
        let manifest = try PerformanceBudgetManifestLoader.loadRepositoryManifest()

        XCTAssertFalse(manifest.scenarios.isEmpty)
        for scenario in manifest.scenarios {
            XCTAssertFalse(scenario.id.isEmpty)
            XCTAssertFalse(scenario.component.isEmpty)
            XCTAssertFalse(scenario.fixtureID.isEmpty)
            XCTAssertTrue(scenario.fixturePolicy.contains("local"), scenario.id)
            XCTAssertLessThanOrEqual(scenario.datasetSize.voxelCount, 512 * 512 * 64, scenario.id)
            XCTAssertGreaterThan(scenario.datasetSize.bytesPerVoxel, 0, scenario.id)
            XCTAssertFalse(scenario.benchmarkCommand.isEmpty, scenario.id)

            for budget in scenario.budgets {
                XCTAssertGreaterThan(budget.releaseLimit, 0, "\(scenario.id) \(budget.stage.rawValue)")
                XCTAssertGreaterThanOrEqual(budget.debugLimit,
                                            budget.releaseLimit,
                                            "\(scenario.id) \(budget.stage.rawValue)")
            }
        }
    }

    func testBudgetEvaluatorMakesWarningsAndFailuresVisible() throws {
        let manifest = try PerformanceBudgetManifestLoader.loadRepositoryManifest()
        let budget = try XCTUnwrap(manifest.budget(stage: .decode,
                                                   metric: .meanTimeMilliseconds,
                                                   scenarioID: "dicom-ct-import-small"))
        let limit = budget.limit(for: .release)

        let passing = PerformanceBudgetSample(scenarioID: "dicom-ct-import-small",
                                              stage: .decode,
                                              metric: .meanTimeMilliseconds,
                                              buildConfiguration: .release,
                                              value: limit * 0.5)
        let warning = PerformanceBudgetSample(scenarioID: "dicom-ct-import-small",
                                              stage: .decode,
                                              metric: .meanTimeMilliseconds,
                                              buildConfiguration: .release,
                                              value: limit * 0.95)
        let failure = PerformanceBudgetSample(scenarioID: "dicom-ct-import-small",
                                              stage: .decode,
                                              metric: .meanTimeMilliseconds,
                                              buildConfiguration: .release,
                                              value: limit + 1)

        let passingEvaluation = try XCTUnwrap(PerformanceBudgetEvaluator.evaluate(passing, manifest: manifest))
        let warningEvaluation = try XCTUnwrap(PerformanceBudgetEvaluator.evaluate(warning, manifest: manifest))
        let failureEvaluation = try XCTUnwrap(PerformanceBudgetEvaluator.evaluate(failure, manifest: manifest))

        XCTAssertEqual(passingEvaluation.status, .pass)
        XCTAssertFalse(passingEvaluation.isVisibleRegression)
        XCTAssertEqual(warningEvaluation.status, .warning)
        XCTAssertTrue(warningEvaluation.isVisibleRegression)
        XCTAssertEqual(failureEvaluation.status, .failure)
        XCTAssertTrue(failureEvaluation.isVisibleRegression)
        XCTAssertEqual(failureEvaluation.limit, limit)
    }

    func testBenchmarkResultAndReporterRecordMemoryAndBuildConfiguration() throws {
        let result = try BenchmarkResult(timings: [0.010, 0.012, 0.011],
                                         peakMemoryBytes: 64 * 1024 * 1024)
        let summary = result.summary()
        XCTAssertTrue(summary.contains("Peak Memory"))
        XCTAssertTrue(summary.contains("64.00 MiB"))

        let suiteResult = BenchmarkSuiteResult(results: [.decoderInit: result],
                                               config: BenchmarkConfig(benchmarkIterations: 3))
        let reporter = BenchmarkReporter(suiteResult: suiteResult)
        let json = try reporter.generateJSON()
        let markdown = reporter.generateMarkdown()

        XCTAssertTrue(json.contains("peakMemoryBytes"))
        XCTAssertTrue(json.contains("buildConfiguration"))
        XCTAssertTrue(json.contains("physicalMemoryBytes"))
        XCTAssertTrue(markdown.contains("Peak Memory"))
        XCTAssertTrue(markdown.contains("Build Configuration"))
    }
}
