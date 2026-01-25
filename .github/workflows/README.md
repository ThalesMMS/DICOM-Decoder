# GitHub Actions CI/CD Workflows

This directory contains automated workflows for continuous integration and testing of the Swift DICOM Decoder library.

## Workflows

### tests.yml

Comprehensive test suite that runs on every push and pull request to `main` and `develop` branches.

**Features:**

1. **macOS Testing**
   - Tests on multiple Xcode versions (15.2, 15.4) for compatibility
   - Runs `swift test` with code coverage enabled
   - Generates and uploads coverage reports to Codecov

2. **iOS Simulator Testing**
   - Tests on multiple iOS versions (17.2, 17.4)
   - Tests on different iPhone simulators (iPhone 15, iPhone 15 Pro)
   - Uses `xcodebuild` for iOS-specific testing
   - Generates iOS-specific coverage reports

3. **Code Quality Checks**
   - Verifies no debug `print()` statements in production code
   - Optional SwiftFormat linting (if `.swiftformat` config exists)
   - Scans for TODO/FIXME comments for awareness

4. **Test Summary**
   - Aggregates results from all test jobs
   - Posts summary to GitHub Actions UI
   - Fails if any test job fails

**Coverage Reporting:**

- Coverage data is generated using Swift's built-in code coverage (`--enable-code-coverage`)
- Reports are converted to lcov format for macOS tests
- Reports are uploaded to Codecov (requires `CODECOV_TOKEN` secret)
- Coverage is tracked separately for macOS and iOS platforms

**Setup Requirements:**

1. **Codecov Integration** (Optional but Recommended)
   - Sign up at https://codecov.io
   - Add repository to Codecov
   - Add `CODECOV_TOKEN` to GitHub repository secrets
   - If not using Codecov, coverage upload steps will be skipped gracefully

2. **Branch Protection** (Recommended)
   - Enable "Require status checks to pass before merging"
   - Select "Test on macOS" and "Test on iOS Simulator" as required checks
   - This ensures all tests pass before code can be merged

**Local Testing:**

To run the same tests locally:

```bash
# macOS tests with coverage
swift test --enable-code-coverage

# View coverage report
xcrun llvm-cov report \
  .build/debug/DicomCorePackageTests.xctest/Contents/MacOS/DicomCorePackageTests \
  -instr-profile .build/debug/codecov/default.profdata

# iOS simulator tests
xcodebuild test \
  -scheme DicomCore-Package \
  -destination 'platform=iOS Simulator,name=iPhone 15 Pro' \
  -enableCodeCoverage YES
```

**Extending the Workflow:**

To add new checks or modify test behavior:

1. Edit `.github/workflows/tests.yml`
2. Test locally using [act](https://github.com/nektos/act) (GitHub Actions local runner)
3. Push changes and verify in Actions tab
4. Monitor for any failures and iterate

**Performance:**

- Full test suite runs in ~5-10 minutes depending on runner availability
- Matrix strategy runs jobs in parallel for faster feedback
- Failed tests provide detailed logs for debugging

**Maintenance:**

- Update Xcode versions as new releases become available
- Update iOS simulator versions to match supported platforms in Package.swift
- Review and update runner versions (`macos-14`) periodically
- Monitor for deprecated GitHub Actions features
