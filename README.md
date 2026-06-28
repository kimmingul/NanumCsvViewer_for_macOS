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
- Excel-style Pivot Builder with field type tags, field search, drag-and-drop plus selection/right-click field assignment, assigned-field move/reorder, filter controls, type-aware value aggregations, multiple measures, totals, and an in-window Pivot Result panel for table and chart output; Values-only, Rows+Values, Columns+Values, and full Rows+Columns+Values layouts are supported.
- Native Swift Charts pivot chart output with grouped bar, stacked bar, bar, and line chart modes, legends, hover tooltips, date-aware defaults, and per-measure chart sections
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

The v1.7 release line improves the v1 no-AI analysis workflow with an interactive Pivot Builder, native Swift Charts pivot output, readable analysis parameter sheets, visible inferred column types, and type-aware pivot measures. Some GitHub v1 roadmap items are still partial rather than complete: broader analytics tools are still inspector/text summaries, column management does not yet include frozen columns, saved views are one per file rather than multiple named bookmarks, and UI customization controls for theme, font, and row density remain follow-up work.

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
