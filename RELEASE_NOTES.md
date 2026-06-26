# Release Notes

## Unreleased

### Features

- Replaced the text-only Pivot Table analysis action with a separate drag-and-drop Pivot Builder window, including table and chart previews.
- Pivot Builder now runs with only a Values field, with Rows+Values, with Columns+Values, or with the full Rows+Columns+Values layout.
- Pivot preview calculation now runs off the main thread and cancels stale aggregation work when the layout changes.
- Reworked the Pivot Builder layout so fields, drop zones, and aggregation controls stay on the left while the table/chart result panel takes the majority of the window.
- Added Pivot Builder field type tags, selection buttons, right-click assignment actions, and a clearer Dimensions versus Measures layout.

## v1.6.1 - 2026-06-26

This patch release applies the post-release v1 roadmap audit fixes and documents the remaining v1/v1.6 gaps. It does not close the full roadmap; graphical analytics, frozen columns, multiple named bookmarks, performance benchmark UI, and UI customization controls remain follow-up work.

### Fixes

- Corrected statistical p-values and 95% confidence intervals to use Student t / gamma-based calculations instead of normal approximations.
- Fixed advanced filter routing so compact comparison expressions such as `age>65`, `age=65`, and `score<=10` are parsed as expressions.
- Fixed JSON export to preserve duplicate headers with stable unique keys such as `value` and `value (2)`.
- Changed JSON export to stream objects row by row instead of materializing the full export array in memory.
- Refactored regex search to compile the regular expression once per search request instead of once per cell.

### Documentation

- Added `ROADMAP_STATUS.md` with the multi-review audit summary and follow-up checklist.
- Updated README and v1.6 release notes so v1.6 is described as a workflow slice rather than full roadmap completion.

### Validation

- `swift test`: 85 tests passing.

### Distribution

- Bundle version: `1.6.1`
- Bundle build: `161`
- Minimum macOS: `14.0`
- Release artifacts:
  - `Nanum-CSV-Viewer-v1.6.1.dmg`
  - `Nanum-CSV-Viewer-v1.6.1.zip`
- SHA-256:
  - `Nanum-CSV-Viewer-v1.6.1.dmg`: `12a204d2e839c0b6ea0e31a37d36d3ea9f0bbd3c1ad78b481fad401ad6c1683f`
  - `Nanum-CSV-Viewer-v1.6.1.zip`: `136235fe46a097997aa3b52ea9ae1d2bf47f9de71237c424541b82c8d4f50ba1`

## v1.6.0 - 2026-06-25

This release ships the first v1.6 viewer workflow slice for day-to-day CSV workflow polish. A later multi-review audit found that some GitHub v1 roadmap items remained partial and should stay open as follow-up work.

### Highlights

- Added native multi-file opening with macOS tab grouping.
- Added drag-and-drop opening for CSV files and CSV text.
- Added clipboard quick import for copied CSV text, file paths, and `file://` URLs.
- Added advanced Find support for plain text, `regex:pattern`, `/pattern/`, and `fuzzy:term`.
- Added per-file saved views for filters, sort keys, hidden columns, search mode, and current column.
- Added an expandable selected value bar for multiline cell contents.
- Added a performance dashboard in the Inspector.
- Added Markdown, JSON, and HTML export formats for the current filtered/sorted view.
- Export now respects currently visible columns when columns are hidden.

### Post-Release Audit Status

- Visual analytics for numeric distributions, date histograms, group-by results, and pivot tables are currently inspector/text summaries rather than Swift Charts views.
- Column management supports hide/show, but frozen columns and persisted reorder workflows are still pending.
- Saved views restore one per-file state; multiple named bookmarks and a picker are still pending.
- The performance dashboard shows row, file, storage, indexing, and throughput metrics; memory metrics and repeatable benchmark UI are still pending.
- Theme, font, and row-density customization controls are still pending beyond system light/dark appearance support.
### Developer Notes

- Added dedicated search query/match types in `CsvCore`.
- Added saved view serialization for stable view-state round trips.
- Added import/routing helpers for clipboard and multi-document open behavior.
- Kept all new behavior covered by focused unit and AppKit regression tests.

### Validation

- `swift test`: 79 tests passing.

### Distribution

- Bundle version: `1.6.0`
- Bundle build: `160`
- Minimum macOS: `14.0`
- Release artifacts:
  - `Nanum-CSV-Viewer-v1.6.0.dmg`
  - `Nanum-CSV-Viewer-v1.6.0.zip`
- SHA-256:
  - `Nanum-CSV-Viewer-v1.6.0.dmg`: `c4a54f348f291ab2b3f6fe1ee3549098eaebf1e432e897eb8d2d0f73015517d3`
  - `Nanum-CSV-Viewer-v1.6.0.zip`: `98dc41a5c0c3adae5a5ba1f7645bc36a14676ed825281bbbe8186fd288dc5598`

## v1.5.0 - 2026-06-24

This release completes the GitHub issue roadmap through v1.5 and includes performance fixes found while testing a real 1.2 GB clinical CSV with large multiline XML/CLOB fields.

### Highlights

- Added column statistics and type inference.
- Added expression-based advanced filtering and direct Go to Row navigation.
- Added export for the current filtered/sorted view.
- Added persistent `.ncvidx` sidecar indexes for faster repeat opens.
- Added enhanced cell inspector and copy formats.
- Added column hide/show controls.
- Added numeric distribution, date histogram, duplicate detection, group-by aggregation, pivot table, and basic statistical analysis tools.

### Performance and Reliability

- Moved persistent sidecar writes outside the indexing completion path.
- Switched sidecar indexes from JSON to a compact binary format.
- Ignored old JSON sidecars without reading the full file.
- Added staged progress reporting for large parallel index builds.
- Skipped sidecar writes when the index sidecar would exceed 256 MiB.
- Bounded table-cell previews for long multiline/XML values so AppKit text layout does not stall on CLOB-heavy CSV files.
- Preserved full cell values in the inspector and copy actions while showing a one-line preview in the grid.

### Validation

- `swift test`: 61 tests passing.
- Real-file performance check: a 1.2 GB multiline XML/CLOB CSV opens through the AppKit controller in 0.336 s with an existing sidecar.
- Cold core indexing check for the same file completed in about 3.7 s via `CsvBench`.

### Distribution

- Bundle version: `1.5.0`
- Bundle build: `150`
- Minimum macOS: `14.0`
- Signing: ad-hoc codesign when no local Developer ID identity is available
- Notarization: not included for ad-hoc builds
- Release artifacts:
  - `Nanum-CSV-Viewer-v1.5.0.dmg`
  - `Nanum-CSV-Viewer-v1.5.0.zip`

## v1.0.1 - 2026-06-24

This patch release fixes intermittent blank or skipped rows in the grid when opening CSV files repeatedly.

### Fixes

- Prevented future row requests during background indexing from being cached as blank rows
- Cleared speculative row cache entries when indexing completes
- Added bounds checks so the grid cannot map visible rows beyond indexed data rows
- Added recovery for malformed first-row quotes that previously caused early physical rows to be swallowed into the header record
- Preserved correct parsing for valid quoted newline records after the malformed-header recovery path
- Added AppKit grid materialization regression tests for repeated small-file opens and rapid same-window reopens
- Added CSV record-indexer regression tests for line breaks at production chunk boundaries

### Performance

Release benchmarking against a 256 MiB synthetic CSV showed no meaningful regression versus `v1.0.0`:

```text
index        0.047-0.063 s
sample rows  3.232-3.759 s  (100,000 sampled rows)
filter       0.072-0.075 s
contains     0.291-0.307 s
```

### Distribution

- Bundle version: `1.0.1`
- Bundle build: `101`
- Minimum macOS: `14.0`
- Signing identity: `Developer ID Application: MINGUL KIM (XB673TQF3A)`
- Notarization: Accepted by Apple notary service and stapled
- DMG layout: includes a `/Applications` drag-and-drop shortcut
- Release artifacts:
  - `Nanum-CSV-Viewer-v1.0.1.dmg`
  - `Nanum-CSV-Viewer-v1.0.1.zip`

## v1.0.0 - 2026-06-24

This is the first stable release of Nanum CSV Viewer for macOS.

### Highlights

- Added the app icon and configured the macOS `.app` bundle icon
- Updated the bundle version to `1.0.0`
- Native macOS large-file CSV viewer built with Swift/AppKit
- Byte-offset indexing and virtual table rendering for CSV files larger than 1 GiB
- Automatic encoding detection for UTF-8, UTF-8 BOM, and CP949/EUC-KR
- Correct handling for quoted newlines, delimiters inside quotes, and escaped quotes
- Apple-style toolbar, filter bar, selected value bar, inspector, and status bar UI
- Search, column filters, selected-cell value filters, and single/multi-column sorting
- `mmap` byte source, parallel no-quote indexing fast path, and fast filter/sort paths
- Developer ID Application signing and Apple notarization/stapling for distribution

### Benchmark

Recent release benchmark result with a 1 GiB synthetic CSV file:

```text
index        0.235 s
filter       0.288 s
contains     1.154 s
sort         4.232 s
```

### Distribution

- Bundle version: `1.0.0`
- Bundle build: `100`
- Minimum macOS: `14.0`
- Signing identity: `Developer ID Application: MINGUL KIM (XB673TQF3A)`
- Notarization: Accepted by Apple notary service and stapled
- Release artifacts:
  - `Nanum-CSV-Viewer-v1.0.0.dmg`
  - `Nanum-CSV-Viewer-v1.0.0.zip`

## v0.1.0 - 2026-06-24

This was the first Developer ID distribution release of Nanum CSV Viewer for macOS.

### Highlights

- Native macOS CSV viewer built with Swift/AppKit
- Byte-offset indexing and virtual table rendering for large CSV files larger than 1 GiB
- Automatic encoding detection for UTF-8, UTF-8 BOM, and CP949/EUC-KR
- Correct handling for quoted newlines, delimiters inside quotes, and escaped quotes
- Apple-style toolbar, filter bar, selected value bar, inspector, and status bar UI
- Search, column filters, selected-cell value filters, and single/multi-column sorting
- `mmap` byte source, parallel no-quote indexing fast path, and fast filter/sort paths
- Developer ID Application signing and Apple notarization/stapling scripts

### Benchmark

Recent release benchmark result with a 1 GiB synthetic CSV file:

```text
index        0.235 s
filter       0.288 s
contains     1.154 s
sort         4.232 s
```

The benchmark file is not committed to the repository and can be regenerated with `CsvBench`.

### Distribution

- Bundle version: `0.1.0`
- Minimum macOS: `14.0`
- Signing identity: `Developer ID Application: MINGUL KIM (XB673TQF3A)`
- Notarization: Accepted by Apple notary service and stapled
- Release artifact: `Nanum-CSV-Viewer-v0.1.0.zip`

### Notes

- This release used `.app` bundle ZIP distribution.
- Installer packages, Sparkle auto-update, and Mac App Store distribution were not included.
- Adding a separate `LICENSE` file was recommended before broader public distribution.
