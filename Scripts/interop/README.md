# DICOM Interop Smoke Tests

This directory contains the opt-in local interop harness for QA-03 (#281).
The regular unit test cycle does not start network services. The smoke tests
only run when `DICOM_INTEROP_SMOKE=1`.

## Local Run

```bash
cd DICOM-Swift
Scripts/interop/run_interop_smoke.sh
```

The script starts local Orthanc and dcm4chee containers, waits for their HTTP
surfaces, exports the endpoint variables consumed by `DicomInteropSmokeTests`,
and writes failure diagnostics to `.build/interop-logs/`.

Use `--orthanc-only` for a quicker local loop, `--keep` to leave services up for
manual debugging, or `--no-up` to run against services you started yourself.

## CI Opt-In

The smoke group is safe to add as an opt-in CI job:

```bash
cd DICOM-Swift
DICOM_INTEROP_SMOKE=1 Scripts/interop/run_interop_smoke.sh
```

The fast test suite can still run all normal unit tests without Docker because
`DicomInteropSmokeTests` skips unless `DICOM_INTEROP_SMOKE=1`.

## Endpoints

Default endpoints:

| Archive | DIMSE | DICOMweb |
| --- | --- | --- |
| Orthanc | `127.0.0.1:4242`, called AE `ORTHANC` | `http://127.0.0.1:8042/dicom-web` |
| dcm4chee | `127.0.0.1:11112`, called AE `DCM4CHEE` | `http://127.0.0.1:8080/dcm4chee-arc/aets/DCM4CHEE/rs` |

The compose file uses `orthancteam/orthanc` and `dcm4che/dcm4chee-arc-psql`
families. Override image tags through `ORTHANC_IMAGE`,
`DCM4CHEE_ARC_IMAGE`, `DCM4CHEE_DB_IMAGE`, and `DCM4CHEE_LDAP_IMAGE` when a
specific local or CI environment needs pinned versions.

## Coverage

`DicomInteropSmokeTests` covers:

- DICOMweb STOW-RS, QIDO-RS, and WADO-RS metadata retrieval.
- DIMSE C-ECHO, C-STORE, and C-FIND for configured archives.
- DIMSE C-GET for archives declaring `dimse-get`.
- C-MOVE into a local Storage SCP (`DicomStorageSCPServer`) and
  received-instance storage for archives declaring `dimse-move` and
  `storage-scp`.
- Stable C-FIND attribute assertions at STUDY and SERIES level (patient
  ID/name, series UID, modality), issue #1223.
- Query cancellation through `DicomDIMSEOperationHandle` surfacing the
  typed `operationCancelled` error.
- Retry-policy and TLS-against-plaintext failure paths surfacing typed
  `DicomNetworkError`s instead of hiding protocol errors.
- Authenticated DICOMweb path against the `orthanc-auth` service (valid
  Basic credentials round-trip STOW/QIDO; invalid credentials surface the
  typed HTTP 401). Local-only credentials: `smoke` /
  `ORTHANC_AUTH_PASSWORD` (default `smoke-secret`).
- WADO-RS metadata `BulkDataURI` resolution and retrieval.
- PHI-free diagnostics: audit events and error bodies are asserted not to
  carry the fixture's patient name/ID.

Failures keep the service logs and Swift test output under
`.build/interop-logs/` so CI artifacts have enough detail for diagnosis.
