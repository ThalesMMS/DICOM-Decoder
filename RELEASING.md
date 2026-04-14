# Releasing `DICOM-Decoder`

This private repository is currently the development and staging home for upcoming `DICOM-Decoder` changes.

## Current release posture

- `DICOM-Decoder` should be treated as **prerelease-only**.
- The reviewed stable release line and public installation snippets still point to `ThalesMMS/DICOM-Decoder`.
- Until that changes deliberately, this repo is for source-based validation, changelog curation, and release-prep review rather than for claiming a stable package release of its own.

## Recommended versioning strategy here

- Keep day-to-day work on `main`.
- Track user-facing changes in `CHANGELOG.md` under `## [Unreleased]`.
- If you need a candidate build from this repo before promotion, prefer a SemVer prerelease tag such as `v1.0.2-rc1` or `v1.1.0-beta1` instead of a stable tag.
- Do not publish a stable `vX.Y.Z` tag from this repo unless you have explicitly decided that this repo, not `DICOM-Decoder`, is now the canonical stable release source.

## Prerelease checklist

Before cutting a prerelease candidate from this repo:

1. Confirm CI is green on `main`.
2. Review `CHANGELOG.md` and make sure `Unreleased` is accurate and user-facing.
3. Re-check README install guidance so it does not imply a stable release from this repo.
4. Run the core package validation locally:
   - `swift build`
   - `swift test`
   - `swift run dicomtool --help`
5. Smoke-test at least one real DICOM decode path and one CLI path that matter for the intended release notes.
6. Capture any manual follow-up needed for promotion to the stable release line.

## First stable release gates for this repo

Do **not** publish a first stable release directly from `DICOM-Decoder` until all of the following are true:

- A deliberate maintainer decision has been made that this repo should own stable releases.
- CI is consistently green for the intended release commit.
- `CHANGELOG.md` is curated and ready to become release notes.
- Install instructions, dependency snippets, and repository links all point to the correct canonical release source.
- Library, CLI, and at least one viewer-facing integration path have been smoke-tested successfully.
- Any artifact/signing/distribution expectations are documented clearly enough that a consumer can repeat them.

## Promotion note

If stable releases continue to be cut from `ThalesMMS/DICOM-Decoder`, use this repo to prepare and validate the change set, then promote the reviewed commit into the stable release line there instead of publishing a separate stable release here.
