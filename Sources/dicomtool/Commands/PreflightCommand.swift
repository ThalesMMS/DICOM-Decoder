//
//  PreflightCommand.swift
//  dicomtool
//
//  Actionable optional-runtime preflight (issue #1219): reports which
//  optional runtimes/fixtures this machine can validate BEFORE running the
//  XCTest suite. Capability definitions, CI policy and require-environment
//  names come from the release-gate manifest
//  (Tests/DicomCoreTests/Resources/ReleaseGates/OptionalRuntimeFixtureManifest.json);
//  this command only contributes the live checks.
//

import ArgumentParser
import DicomCore
import Foundation
#if canImport(Metal)
import Metal
#endif

struct PreflightCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "preflight",
        abstract: "Report optional runtime/fixture capabilities before running the test suite",
        discussion: """
            Reads the optional runtime/fixture manifest and reports, per
            capability: active, missing-optional, regression, or unsupported.

            Exit status is nonzero when a capability that is required — by
            default CI policy or because DICOM_REQUIRE_<CAPABILITY>=1 (or
            DICOM_REQUIRE_OPTIONAL_RUNTIMES=1) is set — is unavailable.
            Missing optional capabilities only produce warnings with setup
            hints.
            """
    )

    @Option(name: .long, help: "DICOM-Swift package root (defaults to the current directory).")
    var packageRoot: String = FileManager.default.currentDirectoryPath

    @Option(name: .long, help: "Path to OptionalRuntimeFixtureManifest.json (defaults to the manifest inside --package-root).")
    var manifest: String?

    @Flag(name: .long, help: "Emit machine-readable JSON instead of the human-readable report.")
    var json = false

    func run() throws {
        let rootURL = URL(fileURLWithPath: packageRoot, isDirectory: true)
        let manifestURL = manifest.map { URL(fileURLWithPath: $0) }
            ?? rootURL.appendingPathComponent(Self.defaultManifestPath)

        let manifest = try PreflightManifest.load(from: manifestURL)
        let environment = ProcessInfo.processInfo.environment
        let entries = manifest.capabilities.map { capability in
            PreflightEntry(
                capability: capability,
                check: Self.check(capabilityID: capability.id, packageRoot: rootURL, environment: environment),
                environment: environment
            )
        }

        if json {
            try printJSON(entries: entries, manifestURL: manifestURL)
        } else {
            printReport(entries: entries, manifest: manifest, manifestURL: manifestURL)
        }

        if entries.contains(where: { $0.isRequiredButUnavailable }) {
            throw ExitCode(1)
        }
    }

    static let defaultManifestPath =
        "Tests/DicomCoreTests/Resources/ReleaseGates/OptionalRuntimeFixtureManifest.json"

    // MARK: - Output

    private func printReport(entries: [PreflightEntry], manifest: PreflightManifest, manifestURL: URL) {
        print("DICOM-Swift optional runtime preflight")
        print("Manifest: \(manifestURL.path) (version \(manifest.version))")
        print("")

        for entry in entries {
            let requirement = entry.isRequired ? "required" : "optional"
            print("[\(entry.check.kind.reportTag)] \(entry.capability.id) (\(requirement)) — \(entry.check.message)")
            if !entry.check.kind.isAvailable {
                print("    setup: \(entry.capability.source)")
                if let requireEnv = entry.requireEnvironmentVariable, !entry.isRequired {
                    print("    require in CI with: \(requireEnv)=1")
                }
            }
        }

        let availableCount = entries.filter { $0.check.kind.isAvailable }.count
        let requiredMissing = entries.filter { $0.isRequiredButUnavailable }
        print("")
        print("Summary: \(availableCount)/\(entries.count) capabilities active, "
            + "\(entries.count - availableCount) inactive, \(requiredMissing.count) required-missing.")
        if requiredMissing.isEmpty {
            print("Result: OK — absent capabilities above are optional (warnings only).")
        } else {
            print("Result: FAIL — required capabilities unavailable: "
                + requiredMissing.map { $0.capability.id }.joined(separator: ", "))
        }
    }

    private func printJSON(entries: [PreflightEntry], manifestURL: URL) throws {
        struct JSONEntry: Codable {
            let id: String
            let kind: String
            let status: String
            let message: String
            let required: Bool
            let requireEnvironmentVariable: String?
            let setupHint: String
        }
        let payload = entries.map { entry in
            JSONEntry(
                id: entry.capability.id,
                kind: entry.capability.kind,
                status: entry.check.kind.rawValue,
                message: entry.check.message,
                required: entry.isRequired,
                requireEnvironmentVariable: entry.requireEnvironmentVariable,
                setupHint: entry.capability.source
            )
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(payload)
        print(String(decoding: data, as: UTF8.self))
    }

    // MARK: - Live checks (keyed by manifest capability id)

    static func check(
        capabilityID: String,
        packageRoot: URL,
        environment: [String: String]
    ) -> PreflightCheck {
        let fixturesDirectory = packageRoot
            .appendingPathComponent("Tests/DicomCoreTests/Fixtures", isDirectory: true)

        switch capabilityID {
        case "bundled-synthetic-fixtures":
            // Mirror of DicomTestRuntimePreflight.status(for: .bundledSyntheticFixtures).
            let requiredFixturePaths = [
                "CT/ct_synthetic.dcm",
                "MR/mr_synthetic.dcm",
                "US/us_synthetic.dcm",
                "XR/xr_synthetic.dcm",
                "Compressed/jpeg_baseline_synthetic.dcm"
            ]
            let missing = requiredFixturePaths.filter {
                !FileManager.default.fileExists(atPath: fixturesDirectory.appendingPathComponent($0).path)
            }
            if missing.isEmpty {
                return PreflightCheck(kind: .available, message: "All bundled synthetic fixtures are present.")
            }
            return PreflightCheck(
                kind: .regression,
                message: "Missing bundled synthetic fixtures: \(missing.joined(separator: ", "))."
            )

        case "large-dicom-fixtures":
            guard let files = FileManager.default.enumerator(
                at: fixturesDirectory,
                includingPropertiesForKeys: [.fileSizeKey]
            ) else {
                return PreflightCheck(kind: .missingOptionalRuntime, message: "Fixtures directory is absent.")
            }
            for case let fileURL as URL in files where fileURL.pathExtension.lowercased() == "dcm" {
                let fileSize = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize
                if (fileSize ?? 0) > 1_000_000 {
                    return PreflightCheck(kind: .available, message: "Found large fixture \(fileURL.lastPathComponent).")
                }
            }
            return PreflightCheck(
                kind: .missingOptionalRuntime,
                message: "No DICOM fixture larger than 1 MB is installed."
            )

        case "jpeg-lossless-conformance-fixtures":
            let directory = fixturesDirectory.appendingPathComponent("Compressed", isDirectory: true)
            guard let files = try? FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil
            ) else {
                return PreflightCheck(kind: .missingOptionalRuntime, message: "Fixtures/Compressed is absent.")
            }
            let losslessFiles = files.filter { url in
                guard url.pathExtension.lowercased() == "dcm" else { return false }
                if url.lastPathComponent.lowercased().contains("lossless") { return true }
                guard let decoder = try? DCMDecoder(contentsOf: url) else { return false }
                let transferSyntax = decoder.info(for: .transferSyntaxUID)
                return transferSyntax.contains("1.2.840.10008.1.2.4.70")
                    || transferSyntax.contains("1.2.840.10008.1.2.4.57")
            }
            if losslessFiles.isEmpty {
                return PreflightCheck(
                    kind: .missingOptionalRuntime,
                    message: "No JPEG Lossless conformance DICOM files are installed."
                )
            }
            return PreflightCheck(
                kind: .available,
                message: "Found \(losslessFiles.count) JPEG Lossless conformance fixture(s)."
            )

        case "charls-runtime":
            let status = DicomCodecRuntimePreflight.status(for: .charLS, environment: environment)
            return PreflightCheck(
                kind: status.isAvailable ? .available : .missingOptionalRuntime,
                message: status.message
            )

        case "openjpeg-runtime":
            let status = DicomCodecRuntimePreflight.status(for: .openJPEG, environment: environment)
            return PreflightCheck(
                kind: status.isAvailable ? .available : .missingOptionalRuntime,
                message: status.message
            )

        case "opj-compress-tool":
            if let path = executablePath(named: "opj_compress", environment: environment) {
                return PreflightCheck(kind: .available, message: "Found opj_compress at \(path).")
            }
            return PreflightCheck(
                kind: .missingOptionalRuntime,
                message: "opj_compress was not found in PATH or common Homebrew locations."
            )

        case "metal-device":
            #if canImport(Metal)
            return MTLCreateSystemDefaultDevice() != nil
                ? PreflightCheck(kind: .available, message: "Metal device is available.")
                : PreflightCheck(kind: .missingOptionalRuntime, message: "No Metal device is available on this host.")
            #else
            return PreflightCheck(kind: .unsupportedFeature, message: "Metal framework is unavailable on this platform.")
            #endif

        case "network-security-tls":
            #if canImport(Network) && canImport(Security)
            return PreflightCheck(kind: .available, message: "Network and Security frameworks are available.")
            #else
            return PreflightCheck(
                kind: .unsupportedFeature,
                message: "Network/Security TLS frameworks are unavailable on this platform."
            )
            #endif

        case "network-interop-smoke":
            #if canImport(Network)
            return environment["DICOM_INTEROP_SMOKE"] == "1"
                ? PreflightCheck(kind: .available, message: "DICOM_INTEROP_SMOKE=1; network smoke tests are enabled.")
                : PreflightCheck(kind: .missingOptionalRuntime, message: "DICOM_INTEROP_SMOKE is not set to 1.")
            #else
            return PreflightCheck(kind: .unsupportedFeature, message: "Network framework is unavailable on this platform.")
            #endif

        default:
            return PreflightCheck(
                kind: .unsupportedFeature,
                message: "No live check is implemented for manifest capability '\(capabilityID)'."
            )
        }
    }

    static func executablePath(named executableName: String, environment: [String: String]) -> String? {
        let pathDirectories = (environment["PATH"] ?? "")
            .split(separator: ":")
            .map(String.init)
        let candidates = (pathDirectories + ["/opt/homebrew/bin", "/usr/local/bin"])
            .map { URL(fileURLWithPath: $0).appendingPathComponent(executableName).path }
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }
}

// MARK: - Manifest model

struct PreflightManifest: Decodable {
    struct CIPolicy: Decodable {
        let `default`: String
        let requiredCapabilityEnv: String
        let networkSmoke: String
    }

    struct Capability: Decodable {
        let id: String
        let kind: String
        let source: String
        let ciBehavior: String
    }

    let version: Int
    let ciPolicy: CIPolicy
    let capabilities: [Capability]

    static func load(from url: URL) throws -> PreflightManifest {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(PreflightManifest.self, from: data)
    }
}

// MARK: - Entry/status model

struct PreflightCheck {
    enum Kind: String {
        case available
        case missingOptionalRuntime = "missing-optional-runtime"
        case regression
        case unsupportedFeature = "unsupported-feature"

        var isAvailable: Bool { self == .available }

        var reportTag: String {
            switch self {
            case .available: return "active "
            case .missingOptionalRuntime: return "missing"
            case .regression: return "REGRESSION"
            case .unsupportedFeature: return "unsupported"
            }
        }
    }

    let kind: Kind
    let message: String
}

struct PreflightEntry {
    static let requireAllEnvironmentVariable = "DICOM_REQUIRE_OPTIONAL_RUNTIMES"

    let capability: PreflightManifest.Capability
    let check: PreflightCheck
    let isRequired: Bool
    let requireEnvironmentVariable: String?

    init(capability: PreflightManifest.Capability, check: PreflightCheck, environment: [String: String]) {
        self.capability = capability
        self.check = check

        // The manifest's ciBehavior carries the per-capability require
        // environment variable name (e.g. "Set DICOM_REQUIRE_CHARLS=1 ...");
        // parse it instead of redefining the mapping here.
        let requireEnv = Self.firstRequireEnvironmentVariable(in: capability.ciBehavior)
        self.requireEnvironmentVariable = requireEnv

        let requiredByDefaultCI = capability.ciBehavior.hasPrefix("Required")
        let requiredByEnvironment = requireEnv.map { environment[$0] == "1" } ?? false
        let requiredByGlobalToggle = capability.kind.hasPrefix("optional")
            && environment[Self.requireAllEnvironmentVariable] == "1"
        self.isRequired = requiredByDefaultCI || requiredByEnvironment || requiredByGlobalToggle
    }

    var isRequiredButUnavailable: Bool {
        isRequired && !check.kind.isAvailable
    }

    static func firstRequireEnvironmentVariable(in ciBehavior: String) -> String? {
        guard let range = ciBehavior.range(
            of: #"DICOM_REQUIRE_[A-Z0-9_]+"#,
            options: .regularExpression
        ) else {
            return nil
        }
        let name = String(ciBehavior[range])
        return name == requireAllEnvironmentVariable ? requireAllEnvironmentVariable : name
    }
}
