# Binary Format Importers — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development
> (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use
> checkbox (`- [ ]`) syntax. Design spec: `docs/superpowers/specs/2026-07-08-binary-format-importers-design.md`.

**Goal:** Add read-only import for legacy `.xls` (BIFF), SPSS `.sav`, and SAS `.sas7bdat` by
running vendored C parsers (`libxls` BSD, `ReadStat` MIT) inside a sandboxed **XPC service**,
feeding the existing temp-CSV bridge. Approach B: the main app never links the C parsers.

**Architecture:** New SPM C targets `CLibXLS` / `CReadStat` (linked only by a new
`ImportService` executable, packaged as `Contents/XPCServices/<id>.xpc`). A shared
`ImportServiceProtocol` target carries the `@objc` interface + `Sendable` DTOs. The main app
gains an XPC client and magic-byte routing; `CsvCore` gains a read-only `ImportMetadata` model
consumed through the existing `ColumnTypeOverride` path.

**Tech Stack:** Swift 6.3 package, Swift 6 language mode, macOS 14 AppKit, XCTest. C targets
via SPM (`SQLite3`/`Compression` precedent). No new `.package(...)` dependency.

## Global Constraints

- Main app / `CsvCore` must NOT link `CLibXLS`, `CReadStat`, or `ImportService`.
- All binary parsing runs in the XPC service; every parse is capped and fail-closed.
- Vendored sources are pinned to an audited commit; local patches documented; licenses bundled.
- `.xls` (Phase 1) ships before `.sav` (Phase 2) before `.sas7bdat` (Phase 3).
- Each phase ends green: `swift test` + a notarizable local build.

---

## Phase 0 — XPC + packaging spike (no parsing)

Prove the riskiest new machinery — SPM → `.xpc` bundle → inside-out signing → notarization,
plus a working `NSXPCConnection` round-trip — with a trivial echo importer and zero parser code.

- [ ] **Task 0.1 — Define the protocol + DTOs.** Create `Sources/ImportServiceProtocol/`
  with `ImportServiceProtocol` (`@objc`), `ImportKind`, `ImportLimits`, `ImportResult`,
  `ImportWarning`, `ImportError` (all `Sendable` + `NSSecureCoding`). Add the target to
  `Package.swift`; app + service depend on it.
  - *Accept:* target builds; DTOs round-trip through `NSKeyedArchiver` in a unit test.
- [ ] **Task 0.2 — Skeleton service.** Create `Sources/ImportService/` executable target with an
  `NSXPCListener` main and an `ImportServiceProtocol` impl that, for `ImportKind.echo`, copies
  the input handle's bytes to `destinationDir/echo.csv` and replies with the path.
  - *Accept:* target builds as an executable.
- [ ] **Task 0.3 — Bundle assembly in the build script.** Extend `Scripts/build-app.sh` to
  assemble the service `Info.plist` (`CFBundlePackageType=XPC!`, `XPCService` dict) + executable
  into `Contents/XPCServices/<id>.xpc`, sign inside-out, and notarize the whole app.
  - *Accept:* `codesign --verify --deep --strict` passes; `spctl -a -t exec` accepts the app;
    notarization staples.
- [ ] **Task 0.4 — Client + round-trip.** Add an `ImportClient` in the app that opens
  `NSXPCConnection(serviceName:)`, calls `echo`, and returns the CSV URL. Wire
  `interruptionHandler`/`invalidationHandler` to a fail-closed error.
  - *Accept:* a manual/integration test opens a text file through the echo path and the temp
    CSV appears; killing the service surfaces the fail-closed error, app survives.
- [ ] **Task 0.5 — Decide `NSXPCConnection` vs `XPCSession`** against current Apple docs; record
  the choice and the file-access transfer mechanism (`NSFileHandle` vs security-scoped bookmark)
  in the design doc's Open Decisions section.

**Gate:** Do not start Phase 1 until an echo import works end-to-end in a notarized local build.

---

## Phase 1 — legacy `.xls` via libxls (plain grid, no metadata)

- [ ] **Task 1.1 — Vendor libxls.** Snapshot `libxls` ≥ 1.6.x `.c/.h` into `Sources/CLibXLS/`
  (+ `include/`); add the C target to `Package.swift` (`publicHeadersPath`, `cSettings`); pin the
  commit; add `LICENSE` + `THIRD_PARTY_NOTICES` entry.
  - *Accept:* `CLibXLS` compiles on Apple Silicon; only `ImportService` links it.
- [ ] **Task 1.2 — Swift wrapper.** In `ImportService`, add `XlsBiffReader` mirroring
  `XlsxWorkbook`'s shape: `hasXlsExtension`, `isXlsFile` (magic bytes), streaming cell callbacks
  → temp CSV, honoring `ImportLimits`. Disable libxls write paths.
  - *Accept:* wrapper unit test converts a fixture `.xls` to the expected CSV; oversized/over-wide
    inputs are rejected; a malformed `.xls` fails closed without crashing the wrapper.
- [ ] **Task 1.3 — Route `.xls`.** Extend `DocumentOpenRouting` to detect OLE2 magic bytes and
  send `.xls` through the XPC client; extend `TempFileCleanup.bridgeDirectoryNames`.
  - *Accept:* app integration test opens a fixture `.xls` and the grid renders via the existing
    CSV engine; parser-process death → fail-closed UX.
- [ ] **Task 1.4 — Fixtures + fuzz.** Add real `.xls` fixtures (encodings, dates, multiple
  sheets → sheet picker parity with `.xlsx`) and a malformed corpus; run the upstream fuzzer
  corpus once.
  - *Accept:* `swift test` green; documented sheet-selection behavior.

**Gate:** `.xls` opens in a notarized local build; docs updated.

---

## Phase 2 — SPSS `.sav` via ReadStat (first-class + metadata bridge)

- [ ] **Task 2.1 — `ImportMetadata` in CsvCore.** Add a read-only `ImportMetadata` model
  (columns → label, declared type, value labels; row count; encoding; warnings) + JSON decode.
  - *Accept:* decode unit test; maps declared types onto `ColumnTypeOverride` categories.
- [ ] **Task 2.2 — Vendor ReadStat.** Snapshot recent `ReadStat` into `Sources/CReadStat/`;
  wire `-liconv`/`-lz` link settings; pin commit; bundle license.
  - *Accept:* `CReadStat` compiles and links iconv/zlib on macOS; only `ImportService` links it.
- [ ] **Task 2.3 — Swift wrapper + sidecar.** Add `SavReader` using ReadStat's variable/value/row
  callbacks → temp CSV + metadata sidecar JSON; honor `ImportLimits`.
  - *Accept:* wrapper test converts a fixture `.sav` to CSV + sidecar matching `pyreadstat`
    output (row/col counts, labels, declared types, missing values).
- [ ] **Task 2.4 — Route + surface metadata.** Detect `$FL2`; route through XPC; on open, apply
  sidecar declared types via `ColumnTypeOverride` and render value labels in cell display.
  - *Accept:* integration test — declared types and value labels visible after opening a `.sav`.
- [ ] **Task 2.5 — Fixtures + fuzz.** `zsav` (compressed), encodings, long strings, many columns;
  malformed corpus; upstream fuzzer pass.
  - *Accept:* `swift test` green.

**Gate:** `.sav` opens with labels/types in a notarized local build; docs updated.

---

## Phase 3 — SAS `.sas7bdat` best-effort (gated)

- [ ] **Task 3.1 — Reuse ReadStat for SAS.** Add `Sas7bdatReader` (+ optional `.sas7bcat` for
  value labels) reusing the `CReadStat` target and the sidecar path.
  - *Accept:* wrapper test converts fixture `.sas7bdat` to CSV + sidecar vs. `pyreadstat`.
- [ ] **Task 3.2 — Best-effort UX.** Detect the SAS header; route through XPC; show a persistent
  "best-effort — verify critical data" banner; surface parser warnings + row/col validation.
  Add a preference to enable/disable SAS import (decide default from demand).
  - *Accept:* integration test — banner shown; disabled state hides the format.
- [ ] **Task 3.3 — Fixtures + fuzz.** Compressed/uncompressed, encodings, dates, catalogs;
  malformed corpus; upstream fuzzer pass.
  - *Accept:* `swift test` green.

**Gate:** ship only if demand materializes; otherwise keep documented as best-effort/deferred.

---

## Cross-Cutting / After All Phases

- [ ] Update `ROADMAP_STATUS.md` (remove items from the deferred list as each ships), `README.md`
  (known-gap language), and `RELEASE_NOTES.md`.
- [ ] Add a `THIRD_PARTY_NOTICES.md` (libxls BSD, ReadStat MIT) and reference it in About.
- [ ] Document the vendored-source refresh process (re-snapshot only on security fixes/needed
  features; re-run fixture + fuzz tests).
- [ ] Confirm App Store sandbox entitlements on both app and service before any MAS submission.

## "Worth it" Rule

Proceed with a format when there is concrete demand (≥3 independent reports or one high-value
user) **and** it surfaces value the UI actually uses (labels/declared types for `.sav`; a real
grid for `.xls`). Otherwise keep it documented as a scoped gap.
