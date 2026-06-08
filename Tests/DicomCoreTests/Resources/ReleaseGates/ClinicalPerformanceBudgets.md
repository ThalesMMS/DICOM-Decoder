# Clinical Performance Budgets

The clinical performance budget manifest is
`Tests/DicomCoreTests/Resources/ReleaseGates/ClinicalPerformanceBudgetManifest.json`.

The current local scenario uses a small non-PHI CT-sized fixture contract and
covers decode, volume assembly, GPU upload, MPR render, volume render, snapshot,
and peak-memory stages for both debug and release comparisons.

Run the budget gate with:

```bash
swift test --package-path DICOM-Swift --filter PerformanceBudgetTests
```
