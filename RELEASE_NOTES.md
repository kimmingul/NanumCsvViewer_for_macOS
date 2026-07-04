# Release Notes

## Unreleased

No unreleased changes.

## v1.8.0 - 2026-07-04

This release brings the macOS app to feature parity with the Windows twin
v1.15: facet analysis, a statistical chart suite, a data quality module, and
Excel workbook import, on top of the Swift 6 migration and grid scroll fixes.

### Features

- Facets panel (View ▸ Facets Panel, F6): a 232pt dock beside the grid showing
  a 6-bin histogram for numeric columns and top-6 value bars for other
  columns. Clicking a bar cross-filters the grid (AND across columns, OR
  within a column); each column's facet excludes its own filter so active
  selections stay visible and toggle off. Numeric range filters persist in
  saved views.
- Visualization menu with seven modeless statistical chart windows built on
  Swift Charts: histogram with KDE overlay and a Shapiro-Wilk badge, grouped
  boxplot with ANOVA, scatter with OLS fit (switching to a density grid past
  20,000 points), correlation heatmap, normal Q-Q plot, date-binned time
  series, and Pareto with cumulative percent. Charts snapshot the current
  view and close automatically when the document changes.
- Data Quality menu (Run Quality Profile, Cmd+Shift+P): a full-file profiler
  that ignores active filters, flags sentinel/missing tokens, mixed-type
  columns with counterexamples, duplicated key-column values, ragged rows,
  and exact duplicate rows, summarizes small categorical domains as a
  codebook, and produces a 0-100 score. Reports export as Markdown, HTML, or
  JSON. (The Windows twin uses Ctrl+Shift+Q; Cmd+Shift+Q is the macOS logout
  chord, so the profile lives on Cmd+Shift+P.)
- Excel workbook import: .xlsx/.xlsm files open through a dependency-free ZIP
  and XML reader with a sheet picker (open one sheet or all sheets in tabs),
  shared strings, cached formula values, booleans, and date-styled serials
  (1900 and 1904 systems) rendered as ISO dates. Legacy .xls remains
  unsupported.
- The detail panel (inspector) is now visible by default on first launch and
  remembers its visibility; Toggle Inspector moved to F4 to match the twin.
- Analysis, chart, and pivot scans cap at 2,000,000 rows and reports state
  "showing first N rows" when the cap applies. Exports and filtering still
  process the full view; Data Quality always scans the whole file.

### Scope Notes

- SPSS .sav and SAS .sas7bdat import (Windows v1.10-1.12) are documented as a
  known gap; see ROADMAP_STATUS.md for the decision record.

### Validation

- `swift test`: 304 tests passing.
- Adversarial review by Codex and Grok advisors; findings adjudicated and
  hardened: Excel header rows now pad to the sheet's true width (columns
  wider than the header were previously inaccessible), ZIP entry guards,
  KDE/Shapiro-Wilk sampling caps, collision-safe duplicate-row hashing,
  facet scan failures surface in the panel, logout-shortcut collision fix.
- Visual smoke tests: facet cross-filtering, all seven chart windows, Excel
  multi-sheet open, and grid interaction verified with screenshots.
- `git diff --check`: passed.
- `Scripts/release-app.sh` (SKIP_NOTARIZE=1): release build and Developer ID
  app signing passed.
- `Scripts/create-dmg.sh`: DMG created and signed
  (`Nanum-CSV-Viewer-v1.8.0.dmg`). Apple notarization not yet submitted.
- Bumped bundle metadata to version `1.8.0(180)`.

## v1.7.6 - 2026-06-28

This patch release fixes Pivot Builder chart hover tooltips so bar and line values are readable without covering the chart.

### Fixes

- Positioned Pivot Builder chart hover tooltips from the selected chart mark instead of a fixed top-right overlay.
- Kept chart hover tooltips compact and opaque so the tooltip no longer stretches across the chart or blends into the plot.
- Prevented chart hover tooltips from participating in hit testing, avoiding mouse-tracking flicker while inspecting bars or line points.
- Added regression coverage for chart-coordinate tooltip placement, non-hit-testing hover behavior, and compact tooltip rendering.
- Bumped bundle metadata to version `1.7.6(176)`.

### Validation

- `swift test --filter PivotBuilderTests`: 43 tests passing.
- `swift test`: 163 tests passing.
- `git diff --check`: passed.
- `Scripts/release-app.sh`: release build and Developer ID app signing passed.
- `Scripts/create-dmg.sh`: DMG creation and signing passed.
- App bundle signing verification: passed.
- DMG signing verification: passed.
- DMG verification: passed.
- App bundle Gatekeeper check: accepted as Notarized Developer ID.
- DMG Gatekeeper check: accepted as Notarized Developer ID.
- Apple notarization:
  - App ZIP submission `102fd106-aa98-4b0e-9ef5-ac32b543485f`: Accepted.
  - DMG submission `29c9764a-11a3-4ff6-aa80-3f3d279f6fe9`: Accepted.

### Distribution

- Bundle version: `1.7.6`
- Bundle build: `176`
- Minimum macOS: `14.0`
- Signing: Developer ID Application
- Notarization: Apple notary service, stapled app and DMG
- Release artifacts:
  - `Nanum-CSV-Viewer-v1.7.6.dmg`
  - `Nanum-CSV-Viewer-v1.7.6.zip`
- SHA-256:
  - `Nanum-CSV-Viewer-v1.7.6.dmg`: `8184f1f3846bd4d9dd708bc6264cdc4945044f18deea30b2915e2af09ac8d8f6`
  - `Nanum-CSV-Viewer-v1.7.6.zip`: `da1199bb174e1d289849c7ac9ee3126ecb96a8f451515ca26aa21b3197d3e706`

## v1.7.5 - 2026-06-28

This patch release improves Pivot Builder chart readability by making chart output use the available Pivot Result panel width.

### Fixes

- Enlarged Pivot Builder charts so the actual Swift Charts view expands with the result pane instead of staying at a narrow intrinsic width.
- Added regression coverage that verifies the chart view is at least 80% as wide as the Pivot Result pane.
- Bumped bundle metadata to version `1.7.5(175)`.

### Validation

- `swift test --filter PivotBuilderTests`: 42 tests passing.
- `swift test`: 162 tests passing.
- `Scripts/release-app.sh`: release build and Developer ID app signing passed.
- `Scripts/create-dmg.sh`: DMG creation and signing passed.
- App bundle signing verification: passed.
- App bundle Gatekeeper check: accepted as Notarized Developer ID.
- DMG signing verification: passed.
- DMG verification: passed.
- DMG Gatekeeper check: accepted as Notarized Developer ID.
- Apple notarization:
  - App ZIP submission `eb835945-2c9e-4554-bc95-04975eaa30fb`: Accepted.
  - DMG submission `0e67bc00-2771-4822-b027-59017c0d9e0d`: Accepted.

### Distribution

- Bundle version: `1.7.5`
- Bundle build: `175`
- Minimum macOS: `14.0`
- Signing: Developer ID Application
- Notarization: Apple notary service, stapled app and DMG
- Release artifacts:
  - `Nanum-CSV-Viewer-v1.7.5.dmg`
  - `Nanum-CSV-Viewer-v1.7.5.zip`
- SHA-256:
  - `Nanum-CSV-Viewer-v1.7.5.dmg`: `dfe489ef372cba136c63f693819ef2ec098b7d2ca385406d88d23be8f6af7a4c`
  - `Nanum-CSV-Viewer-v1.7.5.zip`: `d7092b803eeb0b134e431716c3e1e349f382b6ff58e1950c43169cb85ca938ad`

## v1.7.2 - 2026-06-27

This patch release moves persistent CSV indexes out of source CSV folders and adds settings for managing cached `.ncvidx` files.

### Highlights

- Moved persistent `.ncvidx` files from the CSV file's folder into the app cache folder: `~/Library/Caches/com.nanum.csvviewer.mac/Indexes/`.
- Added `Settings > Delete Index Cache on Close` so users can keep index files temporary and remove the active CSV's cached index when closing it.
- Added `Settings > Show Index Folder` to reveal the index cache folder in Finder.
- Added `Settings > Clear Index Folder` to remove cached index files from the app.
- Moved the existing `Persistent Index` toggle into the new `Settings` menu.
- Cleans up legacy CSV-adjacent `.ncvidx` files during the new cache save/delete flow.

### Validation

- `swift test`: 150 tests passing.
- `git diff --check`: passed.
- App bundle signing verification: passed.
- App bundle Gatekeeper check: accepted as Notarized Developer ID.
- DMG signing verification: passed.
- DMG Gatekeeper check: accepted as Notarized Developer ID.
- Apple notarization:
  - App ZIP submission `edf86836-3bed-4237-b7ac-a75251711aba`: Accepted.
  - DMG submission `fa67cbdc-e9d8-4135-b4d0-89a5e2ad3cec`: Accepted.

### Distribution

- Bundle version: `1.7.2`
- Bundle build: `172`
- Minimum macOS: `14.0`
- Signing: Developer ID Application
- Notarization: Apple notary service, stapled app and DMG
- Release artifacts:
  - `Nanum-CSV-Viewer-v1.7.2.dmg`
  - `Nanum-CSV-Viewer-v1.7.2.zip`
- SHA-256:
  - `Nanum-CSV-Viewer-v1.7.2.dmg`: `6bb6dc8ad8b6bf0c6029e11272282938dc82b525761139b807054d143b31a2ba`
  - `Nanum-CSV-Viewer-v1.7.2.zip`: `e8a2649a1cbe2f7e87d46d57497c40b7dacaec30910c955e7c2e7194a18c07da`

## v1.7.1 - 2026-06-27

This patch release refines the Pivot Builder into a more Excel-like workflow for no-AI v1 analysis, especially for multi-measure pivots and clearer field semantics.

### Highlights

- Added multiple Pivot Builder measures, so one pivot can show several value fields or the same field with several aggregations.
- Added per-measure aggregation controls directly beside each measure field.
- Added type-aware aggregation choices: numeric fields expose Sum, Mean, Median, Min, Max, Std, Count, and Unique Count; categorical, string, date, boolean, and empty fields focus on Count and Unique Count.
- Added measure ordering controls and improved measure-row alignment.
- Reordered field action buttons to Rows, Columns, Filters, Values.
- Kept dimension fields exclusive to one of Rows, Columns, or Filters while allowing repeat use in Values.
- Grouped blank dimension values as `null` in pivot rows, columns, and filters.
- Improved multi-measure result layout with compact top placement, centered result sections, larger spacing between sections, and totals for row/column pivots.
- Added totals while removing the misleading top-left `Total` header from column-only pivot output.
- Made the Filter drop zone compact and gave Measures more vertical space.

### Validation

- `swift test`: 147 tests passing.
- `git diff --check`: passed.
- App bundle signing verification: passed.
- App bundle Gatekeeper check: accepted as Notarized Developer ID.
- DMG signing verification: passed.
- DMG Gatekeeper check: accepted as Notarized Developer ID.
- Apple notarization:
  - App ZIP submission `eeb11d88-39d3-4af4-9cb0-3e6b9ba30222`: Accepted.
  - DMG submission `99c5a1a1-d59a-4005-a44f-26e3e2aaeb67`: Accepted.

### Distribution

- Bundle version: `1.7.1`
- Bundle build: `171`
- Minimum macOS: `14.0`
- Signing: Developer ID Application
- Notarization: Apple notary service, stapled app and DMG
- Release artifacts:
  - `Nanum-CSV-Viewer-v1.7.1.dmg`
  - `Nanum-CSV-Viewer-v1.7.1.zip`
- SHA-256:
  - `Nanum-CSV-Viewer-v1.7.1.dmg`: `49592f06e9baf3d0a0c34b8dd4155e4fc8eccc6be29d9beb8d5c64bbf98b342b`
  - `Nanum-CSV-Viewer-v1.7.1.zip`: `2e0e8947119f39dc7c78e03ff3cda3b0aeee2c9a490fc18330b2880587e01b8c`

## v1.7.0 - 2026-06-27

This release upgrades the no-AI v1 analysis workflow with an Excel-style Pivot Builder, visible inferred column types in the main grid, broader CSV date recognition, and a major type-inference performance fix for string-heavy files.

### Highlights

- Replaced the text-only Pivot Table analysis action with a separate drag-and-drop Pivot Builder window, including table and chart previews.
- Pivot Builder now runs with only a Values field, with Rows+Values, with Columns+Values, or with the full Rows+Columns+Values layout.
- Pivot preview calculation now runs off the main thread and cancels stale aggregation work when the layout changes.
- Reworked the Pivot Builder layout so fields, drop zones, and aggregation controls stay on the left while the table/chart result panel takes the majority of the window.
- Added Pivot Builder field type tags, selection buttons, right-click assignment actions, and a clearer Dimensions versus Measures layout.
- Added Pivot Builder field search plus drag-to-move assigned fields between Rows, Columns, Values, and Filters, including dimension field reordering.
- Expanded CSV date inference for dotted, Korean, month-only, and compact `yyyyMMdd` date formats so Pivot Builder field tags and date analytics recognize more real-world date columns.
- Added inferred type tags to grid headers, with header tooltips that include type and sort state.
- Moved grid header type tags next to the column title so inferred types are visible during normal table scanning.
- Added the inferred type to the grid header fallback title, for example `visit_date [Date]`, so types remain visible even if AppKit does not draw the custom badge.
- Type inference now starts once enough rows are indexed instead of waiting for full-file indexing to finish; final statistics still refresh after indexing completes.
- Numeric distribution and date histogram actions now use inferred column types to choose numeric/date defaults when the selected column is not suitable.

### Fixes

- Fixed the last column header being drawn again in the empty trailing header area.
- Reduced type-tag delay on string-heavy CSV files by skipping date parsing after a column is known to be non-date and by reusing date formatters.

### Validation

- `swift test`: 116 tests passing.
- Real-file type inference check: the 3,224-row, 6-column CP949 CSV used to reproduce the delayed header tags now completes `analyzeColumns` in about 0.095 s after previously taking about 28.19 s.

### Distribution

- Bundle version: `1.7.0`
- Bundle build: `170`
- Minimum macOS: `14.0`
- Signing: Developer ID Application
- Notarization: Apple notary service, stapled app and DMG
- Release artifacts:
  - `Nanum-CSV-Viewer-v1.7.0.dmg`
  - `Nanum-CSV-Viewer-v1.7.0.zip`
- SHA-256:
  - `Nanum-CSV-Viewer-v1.7.0.dmg`: `519f2ad16944a45570cbd7757a14d86b8c7b47094e497a03f63a67ca55a485b1`
  - `Nanum-CSV-Viewer-v1.7.0.zip`: `c4b4cf09964328966576f8e5d8c6e30a49fecb8c1a7591ccf2443c64b833fcf6`

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
