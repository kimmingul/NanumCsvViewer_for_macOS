# Nanum CSV Viewer for macOS

Nanum CSV Viewer is a Swift/AppKit macOS application for opening and inspecting very large CSV files. It is designed to load CSV files larger than 1 GB quickly, keep indexing work in the background, and render rows through a virtual table instead of materializing the whole file in memory.

## Features

- Automatic encoding detection for UTF-8, UTF-8 BOM, and CP949/EUC-KR
- CSV record byte-offset indexing
- Correct handling for quoted newlines, delimiters inside quotes, and escaped quotes
- Recovery for malformed first-row quotes that would otherwise hide following rows
- Virtual row rendering with `NSTableView`
- Background indexing progress
- Column statistics with responsive inferred type tags in grid headers
- Expression-based advanced filters, column filters, and selected-cell value filters
- Advanced find with plain text, `regex:pattern`, `/pattern/`, and `fuzzy:term`
- Go to Row command for direct navigation by source row number
- Export of the current filtered/sorted view as CSV, Markdown, JSON, or HTML
- Persistent `.ncvidx` indexes in the app cache folder for faster repeat opens, with settings to reveal, clear, or delete caches when closing CSV files
- Fast single-column filter and sort paths
- Shift-click multi-column sorting
- Column hide/show controls, selected value bar, filter bar, and Inspector panel
- Saved views for restoring filters, sort order, hidden columns, search mode, and current column per file
- Multi-file opening with native macOS tab support
- Clipboard quick import for CSV text or file paths
- Drag-and-drop import for files and CSV text
- Expandable selected value bar for multiline cells
- Performance dashboard with row, file, storage, indexing, and throughput metrics; memory and repeatable benchmark UI remain roadmap follow-ups
- Bounded one-line table previews for long multiline/XML cells, with full values preserved in the inspector and copy actions
- Text-summary analytics for numeric distribution, date histogram, duplicate detection, group-by aggregation, and basic statistical tests, with numeric/date defaults guided by inferred column types and roomy native parameter sheets for field selection
- Excel-style Pivot Builder with field type tags, field search, drag-and-drop plus selection/right-click field assignment, assigned-field move/reorder, filter controls, type-aware value aggregations, multiple measures, totals, result-table sorting/filtering/copy/export, and an in-window Pivot Result panel for table and chart output; Values-only, Rows+Values, Columns+Values, and full Rows+Columns+Values layouts are supported.
- Native Swift Charts pivot chart output with grouped bar, stacked bar, bar, and line chart modes, legends, stable value hover tooltips, date-aware defaults, and per-measure chart sections sized to fill the Pivot Result panel
- Facets panel (View ▸ Facets Panel, F6): 6-bin histograms for numeric columns and top-6 value bars for other columns beside the grid, with bar-click cross-filtering that composes with text and header filters
- Visualization menu with seven statistical chart windows: histogram with KDE and a Shapiro-Wilk badge, grouped boxplot with ANOVA, scatter with OLS fit and density-grid fallback, correlation heatmap, normal Q-Q plot, date-binned time series, and Pareto
- Extended statistics engine (descriptive statistics, frequency analysis, one-way ANOVA, Shapiro-Wilk normality) with scipy-verified results, plus manual column type override from the header context menu
- Data Quality menu (Cmd+Shift+P): full-file profiler with sentinel, type-validity, key-uniqueness, ragged-row, and duplicate-row rules, a categorical codebook, a 0-100 score, and Markdown/HTML/JSON report export
- Excel .xlsx/.xlsm import with a multi-sheet picker (open one sheet or all sheets in tabs), built on a dependency-free ZIP/XML reader with shared strings and 1900/1904 date serial support; legacy .xls opens read-only through a sandboxed XPC importer
- SPSS .sav/.zsav read-only import with value-label display and declared type metadata, plus best-effort SAS .sas7bdat read-only import with an explicit verification warning
- SQLite .db/.sqlite/.sqlite3 read-only import with a table/view picker through the same temp-CSV bridge
- macOS light and dark appearance support
- 1 GiB CSV benchmark CLI

## Project Structure

```text
NanumCsvViewerMac/
  Package.swift
  Sources/
    CsvCore/              # Large-file CSV engine
    NanumCsvViewerMac/    # AppKit UI
    CsvBench/             # 1 GiB benchmark CLI
  Tests/CsvCoreTests/     # CSV parser, index, filter, search, export, and sort tests
  Tests/NanumCsvViewerMacTests/
                         # AppKit grid, import, routing, search parser, and UI state tests
  Scripts/build-app.sh    # .app bundle creation script
```

## Requirements

- macOS 14 or later
- Swift 6.x / Xcode command line tools

## Build and Test

```bash
cd NanumCsvViewerMac
swift build
swift test
```

If SwiftPM cannot write to the default module cache, use a local cache path:

```bash
CLANG_MODULE_CACHE_PATH=../.clang-cache swift build
CLANG_MODULE_CACHE_PATH=../.clang-cache swift test
```

## Run the App

```bash
cd NanumCsvViewerMac
swift run NanumCsvViewerMac
```

## v1.10.0 User Workflows

- **Open legacy `.xls` files.** BIFF workbooks now open read-only through a sandboxed XPC importer while the existing pure-Swift `.xlsx`/`.xlsm` reader remains unchanged.
- **Open SPSS files.** `.sav` and `.zsav` files import read-only through the same temp-CSV bridge, preserving value labels for display and declared type metadata for grid type badges.
- **Open SAS files.** `.sas7bdat` files import read-only as best-effort and show a persistent warning to verify critical data against SAS.
- App bundle metadata now uses version `1.10.0(200)`.

## v1.9.0 User Workflows

- **Choose an export encoding.** File ▸ Export… now shows an encoding popup (UTF-8, UTF-8 with BOM, or CP949 / EUC-KR) and an option to reveal the file in Finder afterward. Encoding applies to CSV; JSON/HTML/Markdown stay UTF-8. A CP949 export warns if any character could not be represented.
- **Switch appearance and font size.** View ▸ Appearance sets System / Light / Dark for the whole app; View ▸ Font Size sets Small / Medium / Large grid text. Both are remembered across launches and combine with Row Density.
- **Benchmark the current view.** View ▸ Run Benchmark (⌥⌘B) times full-scan, search, and distinct-value passes and reports rows/second — repeatable and read-only.
- App bundle metadata now uses version `1.9.0(190)`.

## v1.8.2 Notes

- Analysis, charts, and pivots now stream the current view instead of loading it entirely into memory, so large-file analysis stays within a bounded memory footprint. Results are unchanged.
- The app cleans up its temporary Excel/SQLite bridge files and clipboard-import files on launch, and prunes saved-view bookmarks for deleted files.
- App bundle metadata now uses version `1.8.2(182)`.

## v1.8.1 User Workflows

- Save several named views per file with `View > Save View As...`, switch between them from `Restore Saved View...`, and enable `Restore View on Open` to reapply the most recent one automatically.
- Toggle individual columns from the `View > Columns` checklist, drag column headers to reorder them (the order is remembered per file and exports follow it), and right-click a header to `Pin Column to Front` so an identifier column stays leftmost.
- Change grid row height with `View > Row Density`, and check the process memory footprint in the performance dashboard.
- App bundle metadata now uses version `1.8.1(181)`.

## v1.8.0 User Workflows

- Toggle `View > Facets Panel` (F6) to see per-column value distributions beside the grid; click a bar to cross-filter, click it again to remove the filter, and click more bars in the same column to widen the selection.
- Open `Visualization` menu charts in their own windows: histogram + KDE, boxplot + ANOVA, scatter + regression, correlation heatmap, Q-Q plot, time series, and Pareto. Chart windows snapshot the current filtered view and close when the document changes.
- Run `Data Quality > Run Quality Profile` (Cmd+Shift+P) to profile the entire file regardless of active filters, then export the report as Markdown, HTML, or JSON.
- Open Excel workbooks from `File > Open...` or drag and drop; multi-sheet workbooks show a sheet picker with an "Open All in Tabs" option.
- The Inspector panel is visible by default on first launch (toggle with F4) and remembers its visibility.
- Analysis, chart, and pivot scans cap at 2,000,000 rows and reports say "showing first N rows" when the cap applies; exports and filtering always use the full view.
- App bundle metadata now uses version `1.8.0(180)`.

## v1.7.7 User Workflows

- Use the Pivot Builder's `Pivot Table` tab to sort pivot result columns by clicking headers while keeping total rows pinned at the bottom.
- Use the Pivot Result toolbar to filter visible pivot result rows, copy the result table as tab-separated text, or export the result table as CSV.
- Pivot result tables now keep one visible header row, fill the available width without a blank trailing header area, and preserve adjusted column widths after sort/filter refreshes.
- App bundle metadata now uses version `1.7.7(177)`.

## v1.7.6 User Workflows

- Use the Pivot Builder's `Pivot Chart` tab to inspect bar and line chart values with stable hover tooltips that stay compact, opaque, and positioned near the selected mark.
- Pivot chart hover tooltips now show the selected category, measure/series name, and value without stretching across the chart or interrupting mouse tracking.
- App bundle metadata now uses version `1.7.6(176)`.

## v1.7.5 User Workflows

- Use the Pivot Builder's `Pivot Chart` tab to view charts that expand across the Pivot Result area instead of staying at the SwiftUI chart's narrow default width.
- Pivot charts now keep the chart view at least 80% as wide as the result pane, which makes dense grouped or line charts easier to read on wide windows.
- App bundle metadata now uses version `1.7.5(175)`.

## v1.7.4 User Workflows

- Use the app menu's `Nanum CSV Viewer 정보` command to open the custom About window, which now shows the app icon, version, copyright, developer name, and both affiliations in a compact macOS-style layout.
- The top-level app menu name is explicitly set to `Nanum CSV Viewer` and is excluded from decorative menu icons so it no longer overlaps with an icon beside the Apple menu.
- App bundle metadata now includes `CFBundleDisplayName` and version `1.7.4(174)`.

## v1.7.3 User Workflows

- Open several CSV files at once from `File > Open...`; additional files open in native macOS tabs.
- Drag CSV files or CSV text onto the empty state or table area to open them quickly.
- Use `File > Open from Clipboard` to open copied CSV text, a copied file path, or a copied `file://` URL.
- Use the toolbar Find field with:
  - plain text for case-insensitive contains search
  - `regex:pattern` or `/pattern/` for regular expressions
  - `fuzzy:term` for ordered-character fuzzy matching
- Use `View > Save Current View` and `View > Restore Saved View` to keep a per-file view state.
- Use `View > Performance Dashboard` to inspect row counts, storage mode, indexing time, and throughput.
- Use `Settings > Show Index Folder` or `Settings > Clear Index Folder` to manage cached `.ncvidx` files. `Settings > Delete Index Cache on Close` keeps cache files temporary by removing the active CSV's index when the CSV is closed.
- Use the grid header tags to quickly check inferred column types. Analysis actions and Pivot Builder field tags use the same type inference, including common CSV date formats such as dotted, Korean, month-only, and compact `yyyyMMdd` dates. Type tags are calculated early during indexing and avoid slow date parsing for obvious non-date text columns.
- Use `Pivot > Pivot Table` or the toolbar Pivot button to open the Pivot Builder, then search and add fields by dragging, using the field buttons, or right-clicking a field. Assigned field chips can be dragged between Rows, Columns, Filters, and Values, and dimension chips can be reordered. Values are measures with per-field aggregation controls; the same field can be added multiple times as separate measures, for example Mean, Std, Min, and Max for one numeric column. Rows, Columns, and Filters are dimensions, blank dimension values are grouped as `null`, Rows and Columns are optional, and the Pivot Table and Pivot Chart tabs update in the builder's large result panel with per-measure results and totals. Pivot Chart uses native Swift Charts with chart-type switching, legends, hover tooltips, and line defaults for date-grouped categories.
- Run `Analysis` menu tools from the menu to open a dedicated parameter sheet for numeric distribution, date histogram, duplicate rows, group-by, correlation, t-test, and chi-square. These sheets use wider field controls and fixed action buttons so long column names and Korean labels remain readable.
- Use `File > Export as Markdown...`, `Export as JSON...`, or `Export as HTML...` to share the current filtered/sorted view with only visible columns.
- Expand the selected value bar with the chevron button when a selected cell contains multiline content.

## Roadmap Audit Status

The v1.8 release reached feature parity with the Windows twin v1.15. The binary import follow-up adds read-only legacy `.xls`, SPSS `.sav`/`.zsav`, and best-effort SAS `.sas7bdat` through a sandboxed XPC service with vendored C parsers; the main app and `CsvCore` do not link those parser targets. Some GitHub v1 roadmap items remain partial: column management does not yet include frozen columns, saved views are one per file rather than multiple named bookmarks, and UI customization controls for theme, font, and row density remain follow-up work.

See `ROADMAP_STATUS.md` for the detailed issue-by-issue audit and follow-up list.

To create a macOS `.app` bundle:

```bash
cd NanumCsvViewerMac
Scripts/build-app.sh
open "dist/Nanum CSV Viewer.app"
```

To create an installable DMG with an `Applications` drag-and-drop shortcut:

```bash
cd NanumCsvViewerMac
Scripts/build-app.sh
DEVID_APP="Developer ID Application: MINGUL KIM (XB673TQF3A)" Scripts/sign-app.sh
DEVID_APP="Developer ID Application: MINGUL KIM (XB673TQF3A)" Scripts/create-dmg.sh
```

## Developer ID Signing and Notarization

For distribution outside the Mac App Store, sign the app with an Apple Developer ID Application certificate and notarize it with Apple.

First, confirm that a Developer ID Application certificate is installed in the local keychain:

```bash
security find-identity -v -p codesigning
```

If it is not installed, add it from Xcode:

```text
Xcode > Settings > Accounts > Manage Certificates > Developer ID Application
```

Build and sign the app bundle:

```bash
cd NanumCsvViewerMac
Scripts/build-app.sh
DEVID_APP="Developer ID Application: MINGUL KIM (XB673TQF3A)" Scripts/sign-app.sh
```

To specify a different signing identity:

```bash
SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID1234)" Scripts/sign-app.sh
```

Notarization credentials can be provided through a `notarytool` keychain profile or an App Store Connect API key.

```bash
xcrun notarytool store-credentials "nanum-notary" \
  --apple-id "you@example.com" \
  --team-id "TEAMID1234" \
  --password "app-specific-password"
```

Notarize and staple the app:

```bash
NOTARYTOOL_PROFILE="nanum-notary" Scripts/notarize-app.sh
```

The release scripts also support the environment variable names used by the local `notepad_macOS` project:

```bash
DEVID_APP="Developer ID Application: MINGUL KIM (XB673TQF3A)" \
NOTARY_PROFILE="notary-profile" \
Scripts/release-app.sh
```

When using an App Store Connect API key:

```bash
ASC_KEY_ID="XXXXXXXXXX" \
ASC_ISSUER_ID="xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx" \
Scripts/notarize-app.sh
```

The default API key path is:

```text
~/.appstoreconnect/private_keys/AuthKey_<ASC_KEY_ID>.p8
```

To build, sign, notarize, and staple in one step:

```bash
NOTARYTOOL_PROFILE="nanum-notary" Scripts/release-app.sh
```

To verify signing without notarization:

```bash
SKIP_NOTARIZE=1 Scripts/release-app.sh
```

If a Developer ID certificate is not available, ad-hoc signing can be used for local verification only:

```bash
SIGN_IDENTITY="-" SKIP_NOTARIZE=1 Scripts/release-app.sh
```

Ad-hoc signed builds are not notarized and are not a substitute for Developer ID distribution.

## Mac App Store Build

Mac App Store distribution uses a separate bundle identifier, sandbox entitlement, signing identity, and package format from Developer ID distribution.

Default App Store bundle identifier:

```text
com.nanumspace.mgkim.nanumcsvviewer
```

Build and sign a sandboxed App Store app bundle:

```bash
cd NanumCsvViewerMac
Scripts/build-appstore-app.sh
```

Create a Mac App Store product archive:

```bash
Scripts/package-appstore.sh
```

The App Store build uses:

- `Config/AppStore.entitlements`
- `Apple Distribution: MINGUL KIM (XB673TQF3A)` for the app bundle
- `3rd Party Mac Developer Installer: MINGUL KIM (XB673TQF3A)` for the `.pkg`
- `productbuild --component ... /Applications`, which is the supported product archive mode for Mac App Store submission

Upload requires App Store Connect authentication. `altool` does not use the Xcode GUI login automatically, so provide either an App Store Connect API key:

```bash
ASC_KEY_ID="XXXXXXXXXX" \
ASC_ISSUER_ID="xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx" \
Scripts/upload-appstore.sh
```

or Apple ID upload credentials:

```bash
APPLE_ID="you@example.com" \
APPLE_APP_PASSWORD="app-specific-password" \
APPLE_PROVIDER_PUBLIC_ID="provider-id" \
Scripts/upload-appstore.sh
```

The private key file for API-key upload should be available where `altool` can find it, such as:

```text
~/.appstoreconnect/private_keys/AuthKey_<ASC_KEY_ID>.p8
```

## Benchmark

The 1 GiB benchmark CSV is not committed to the repository. Generate it when needed:

```bash
cd NanumCsvViewerMac
swift build -c release --product CsvBench
.build/release/CsvBench --generate
```

Then run the benchmark against the generated file:

```bash
.build/release/CsvBench
```

Recent 1 GiB benchmark result:

```text
index        0.235 s
filter       0.288 s
contains     1.154 s
sort         4.232 s
```

Benchmark file:

```text
NanumCsvViewerMac/BenchmarkData/one_gib.csv
```

This file is excluded by `.gitignore` because of its size.

## Performance Design

- The app indexes record start offsets instead of pre-parsing every row into memory.
- Only visible rows are decoded and retained in an LRU cache.
- Table cells render bounded previews so very long XML/CLOB fields do not trigger expensive AppKit text layout.
- Rows requested before indexing completes are not cached as blank rows.
- Simple CSV files without quotes use a parallel newline-scan indexing fast path.
- Quoted CSV files fall back to the accurate state-machine indexer.
- Persistent cache index writes are performed outside the load-completion path and skipped when the `.ncvidx` file would be too large.
- Malformed first-row quote recovery is isolated to suspicious headers so valid quoted newline records still use the normal parser.
- Column equality and contains filters extract only the selected column instead of parsing full rows.
- Single-column sorting extracts only sort keys to reduce parsing cost.
- On macOS, the engine prefers an `mmap` byte source and falls back to a `pread`-based source when needed.

## License

Nanum CSV Viewer is available under the MIT License. See [LICENSE](LICENSE) for details.
