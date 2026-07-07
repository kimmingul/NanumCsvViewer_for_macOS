# Binary Format Importers (SPSS / SAS / legacy .xls) — Design

## Goal

Close the last three deferred roadmap gaps (`ROADMAP_STATUS.md:94`) by adding read-only
import for **legacy Excel `.xls` (BIFF)**, **SPSS `.sav`**, and **SAS `.sas7bdat`**.
Do it without adding a Swift package dependency, without reimplementing reverse-engineered
binary formats by hand, and without exposing the main app to memory-unsafe C parsing of
untrusted files.

## Decision Record (why this shape)

- **Vendor C libraries, do not reimplement.** `libxls` (BSD) reads `.xls`; `ReadStat` (MIT)
  reads `.sav`/`.sas7bdat`. Both are permissive-licensed and battle-hardened through R
  (`haven`, `readxl`), Python (`pyreadstat`), and DuckDB. A solo maintainer cannot match
  their edge-case coverage in pure Swift. Vendoring their **source** as SPM C targets keeps
  `Package.swift` at zero external `.package(...)` entries — the same spirit as the existing
  `import SQLite3` / `import Compression` system-library precedent.
- **Approach B — run the C parsers out-of-process in a sandboxed XPC service.** The parsers
  consume untrusted binary files; the main app must never link them. Process isolation
  contains any crash/exploit and is the App-Sandbox-sanctioned mechanism (a plain child
  process is restricted under sandbox), so it also fits the future Mac App Store goal.
  (Triad advisory: Codex + Grok, `.omc/artifacts/ask/`, 2026-07-07.)
- **SPSS first-class, SAS best-effort.** `.sav` is documented and reliably parsed; `.sas7bdat`
  is reverse-engineered and carries silent-correctness risk, so it ships with explicit
  warnings and may be off by default.

## Scope

- Read-only import of `.xls`, `.sav`, `.sas7bdat` into the existing CSV engine via the
  established **temp-CSV bridge** (same pattern as `XlsxWorkbook` / `SqliteWorkbook`).
- All binary parsing happens inside a dedicated, sandboxed **XPC service**; the main app
  links only a small `@objc` protocol + a connection client.
- SPSS value labels and declared column types (Currency/Percent/Ordinal/Scientific) are
  preserved across the bridge via a **metadata sidecar** and surfaced through the existing
  `ColumnTypeOverride` machinery.
- Phased delivery: `.xls` → `.sav` → `.sas7bdat`.

## Out of Scope

- Writing/exporting to `.xls`/`.sav`/`.sas7bdat` (viewer stays read-only for these).
- SAS catalog-only workflows beyond value labels (`.sas7bcat` used only for labels).
- Full SPSS/SAS semantic parity (multiple-response sets, SPSS syntax, weighting).
- Streaming a binary source without a temp CSV (the bridge is the deliberate design).
- Replacing the pure-Swift `.xlsx` reader (unaffected).

## Architecture

### Target / module layout (repo-root relative)

```
NanumCsvViewerMac/
  Sources/
    CLibXLS/                vendored BSD C + include/         ← linked ONLY by ImportService
    CReadStat/              vendored MIT C + include/,
                            links system iconv + zlib          ← linked ONLY by ImportService
    ImportServiceProtocol/  @objc protocol + Sendable DTOs     ← linked by app AND service
    ImportService/          executable, packaged into a .xpc   ← Swift wrappers over the C
    CsvCore/                unchanged; gains ImportMetadata model only
    NanumCsvViewerMac/      unchanged app; gains an XPC client + routing
```

The main app **must not** depend on `CLibXLS` / `CReadStat` / `ImportService`. It depends on
`ImportServiceProtocol` only. This is the load-bearing invariant of Approach B.

### The XPC service

- A bundled XPC service (`Contents/XPCServices/<id>.xpc`), launchd-managed, one process per
  connection, with its **own** `Info.plist` and **own, tighter** sandbox entitlements:
  `com.apple.security.app-sandbox` = YES, **no** `network.client`, hardened runtime, no JIT.
  File access limited to the handed-in source file and the shared temp bridge directory.
- Interface (`@objc public protocol ImportServiceProtocol`):
  `inspectFile(_ handle: NSFileHandle, kind: ImportKind, limits: ImportLimits,
   reply: (ImportInspection?, ImportError?) -> Void)` for lightweight workbook metadata needed
  before import, currently `.xls` sheet names only.
  `importFile(_ handle: NSFileHandle, kind: ImportKind, limits: ImportLimits,
   destinationDir: URL, reply: (ImportResult?, ImportError?) -> Void)`.
  `ImportInspection` = sheet names. `ImportResult` = temp CSV URL + optional metadata sidecar
  URL + `[ImportWarning]` + row/col counts. All DTOs are `Sendable` and `NSSecureCoding`.
- The connection client owns `interruptionHandler`/`invalidationHandler`: a parser crash
  surfaces as a clean, user-facing "could not read this file" (fail-closed), and the main app
  stays alive.

### Data / control flow (open a binary file)

1. Open → main app resolves the file to a security-scoped URL and opens an `NSFileHandle`.
2. `DocumentOpenRouting` detects the format by magic bytes
   (`.xls` = OLE2 `D0 CF 11 E0`; `.sav` = `$FL2`; `.sas7bdat` header signature) and routes to
   the XPC import client instead of the CSV engine.
3. Client opens `NSXPCConnection`, sends the file handle + `ImportLimits`
   (max bytes / rows / cols / cells + wall-clock timeout) + the temp destination dir.
4. Service: enter security scope → C parser via **streaming callbacks** → write temp CSV
   (and, for `.sav`/`.sas7bdat`, a metadata sidecar JSON of column labels/types/value-labels)
   → return paths + warnings, or a typed error.
5. Main app opens the temp CSV via the existing `VirtualCsvDocument`; applies sidecar declared
   types through `ColumnTypeOverride`; shows a warning banner for SAS best-effort.
6. `TempFileCleanup` sweeps the bridge dir on launch (already implemented) — extend its
   `bridgeDirectoryNames` to cover the new importers.

### Metadata sidecar (why the bridge must grow for `.sav`)

The current temp-CSV bridge is flat CSV, which would **discard** the value labels and declared
types that are the entire reason `.sav`/`.sas7bdat` are worth importing. The service therefore
emits a small JSON sidecar next to the temp CSV:

```
{ "columns": [ { "name": "...", "label": "...", "declaredType": "percent|currency|...",
                 "valueLabels": { "1": "Yes", "2": "No" } } ],
  "rowCount": N, "encoding": "...", "warnings": [ ... ] }
```

`CsvCore` gains a read-only `ImportMetadata` model; the app applies declared types via the
existing `ColumnTypeOverride` path and can render value labels in cell display. `.xls` produces
no sidecar (plain grid), which is exactly why it is Phase 1.

## Security Model (the point of Approach B)

- **Physical isolation.** Memory-unsafe C cannot corrupt main-app memory or reach user data
  beyond the single handed-in file.
- **Least privilege.** Service entitlements deny network and broad file access; hardened
  runtime; write paths in the vendored libraries disabled where possible.
- **Pre-parse resource caps.** File-size ceiling, row/col/cell ceilings, wall-clock timeout →
  cancel and fail-closed. Reject early, before allocating on attacker-controlled sizes.
- **Hardened snapshots only.** `libxls` ≥ 1.6.x (post-2018 security rewrite: libFuzzer, error
  returns instead of `exit()`), recent `ReadStat` (OSS-Fuzz coverage). Pin exact commit; keep
  local patches documented; keep a fuzz/malformed corpus.
- **No metadata-driven side effects.** Parsed metadata never influences filesystem paths or
  shell invocation.

## Correctness & Trust

- **SPSS `.sav`:** ship as supported once fixture comparisons against `pyreadstat`/`haven`
  outputs pass (row/col counts, labels, declared types, missing values, encodings).
- **SAS `.sas7bdat`:** ship labeled "best-effort — verify critical data against SAS." Post-parse
  validation surfaces row/col counts and parser warnings; consider off-by-default behind a
  preference. Never claim SAS-grade fidelity.
- **Legacy `.xls`:** lowest semantic ambiguity; treat as supported once fixture tests pass.

## Error Handling

- Any parse failure, malformed structure, or cap breach → clear "could not reliably read this
  file" message; never present garbage as data; offer cancel / open-as-raw-text.
- Service-process death → connection invalidation handler → same fail-closed path.
- Unsupported sub-features (e.g. an exotic BIFF record) → warning, not silent drop, when the
  row/column shape is still trustworthy.

## Packaging & Notarization

- SPM does not emit `.xpc` bundles. The existing app-bundle build scripts
  (`Scripts/build-app.sh`, `build-appstore-app.sh`) gain a step that assembles the service
  bundle (service `Info.plist` with `CFBundlePackageType=XPC!` and the `XPCService` dict) into
  `Contents/XPCServices/`.
- Sign **inside-out** (service before app; avoid `codesign --deep`); notarize the whole app so
  the nested `.xpc` is covered. App Store build gets the sandbox entitlements on both app and
  service.

## Testing

- **CSV/core:** `ImportMetadata` decode; declared-type mapping into `ColumnTypeOverride`.
- **Service (unit, in-process wrappers):** each C wrapper converts fixture files to expected
  CSV + sidecar; cap enforcement rejects oversized/over-wide inputs; malformed files fail
  closed without crashing the wrapper.
- **App (integration):** routing by magic bytes; connection interruption → fail-closed UX;
  `.sav` declared types visible after open; SAS warning banner shown.
- **Fixtures:** real exports across encodings, dates/times, labels, missing values, long
  strings, many columns, compressed (`zsav`, compressed `sas7bdat`); plus a malformed corpus.
- **Fuzzing:** run upstream corpora + a handful of adversarial files before releases.

## Open Decisions to Verify During Implementation

- **Phase 0 decision, 2026-07-08:** use `NSXPCConnection(serviceName:)` rather than
  `XPCSession`. Apple documents `NSXPCConnection` as the Foundation RPC API for bundled XPC
  services, with `@objc` protocol interfaces, `NSSecureCoding` arguments/replies,
  `NSXPCListener.serviceListener`, and `interruptionHandler`/`invalidationHandler`. The current
  macOS SDK exposes `XPCSession`, but its public Swift interface is dictionary/Codable-message
  oriented; it does not match this design's load-bearing `@objc` protocol boundary as directly.
- **Phase 0 decision, 2026-07-08:** assemble
  `Contents/XPCServices/com.nanum.csvviewer.ImportService.xpc` with top-level
  `CFBundleIdentifier`, `CFBundleExecutable`, `CFBundlePackageType=XPC!`, and an `XPCService`
  dictionary. Use `ServiceType=Application` (the default for app-embedded private services) and
  `RunLoopType=NSRunLoop` so the Swift service's `NSXPCListener.serviceListener` can own the
  process lifetime.
- **Phase 0 decision, 2026-07-08:** pass explicit POSIX file descriptors wrapped in
  `NSSecureCoding` DTOs that use `NSXPCCoder.encodeXPCObject(xpc_fd_create(...))` /
  `decodeXPCObject(ofType: XPC_TYPE_FD, ...)`. The initial direct `NSFileHandle` spike failed in
  the real bundled app: `NSFileHandle` attempted secure-coder serialization and threw
  `NSFileHandleOperationException` before the message reached the service. A bookmark fallback was
  also unsuitable for headless/non-user-selected sources. The final Phase 0 bridge has the app
  pre-create the temp CSV and hand the service only a read descriptor for the source and a write
  descriptor for the bridge file; the sandboxed service does not need broad path access.
- **Phase 2 decision, 2026-07-08:** `CReadStat` links system `libiconv` and `libz` from SPM
  with `.linkedLibrary("iconv")` and `.linkedLibrary("z")`, plus `HAVE_ZLIB=1`. `swift build
  --target ImportService` proves the target compiles and links without adding any external
  `.package(...)` dependency.
- **Phase 3 decision, 2026-07-08:** SAS `.sas7bdat` import is enabled by default because this
  feature branch was explicitly requested through Phase 3, but it remains gated by the
  `NanumCsvViewerMac.SasImportEnabled` user default and always shows a persistent best-effort
  verification warning.

## Phase 1 Implementation Notes — legacy `.xls`

- `libxls` is vendored at `v1.6.3`
  (`c199d132494833da696b58aa4acf3fc5a36d930b`) under
  `NanumCsvViewerMac/Sources/CLibXLS`. The vendored target contains reader library sources only;
  the upstream `xls2csv` CLI is not linked into the app.
- Only `ImportService` depends on `CLibXLS`. The app target depends on `ImportServiceProtocol`
  and uses OLE2 magic-byte detection plus XPC calls for `.xls`.
- `.xls` sheet selection matches the `.xlsx` workflow for supported BIFF workbooks: the app asks
  the XPC service for sheet names through `inspectFile`; a single-sheet workbook opens directly,
  while a multi-sheet workbook shows a read-only sheet picker before importing the selected sheet
  to the temp-CSV bridge.
- The upstream libxls fuzz corpus is bundled as importer test fixtures. The Phase 1 smoke test
  feeds each corpus file through the wrapper with resource caps and verifies parser failures leave
  no partial CSV.

## Phase 2 Implementation Notes — SPSS `.sav`

- `ReadStat` is vendored at
  `3c68974fbb35c5bf0888fd603cd99b8253477359` under
  `NanumCsvViewerMac/Sources/CReadStat`. The SPM target compiles the binary reader sources needed
  for SPSS/SAS and excludes format-specific writer implementations.
- Only `ImportService` depends on `CReadStat`. The app target routes `.sav` by `$FL2` magic bytes
  and depends only on `ImportServiceProtocol`.
- `.sav` and `.zsav` import write a temp CSV plus `import.csv.metadata.json`. The sidecar preserves
  column labels, declared types, value labels, row count, encoding, and warnings. The app applies
  declared types through `ColumnTypeOverride` and displays value labels in grid cells.

## Phase 3 Implementation Notes — SAS `.sas7bdat`

- `.sas7bdat` reuses the same `CReadStat` target and sidecar bridge. The app detects the SAS magic
  bytes at offset 12 and routes only when `NanumCsvViewerMac.SasImportEnabled` is true.
- SAS import is read-only and best-effort. Imported documents show a persistent warning:
  "SAS import is best-effort; verify critical data against SAS."
