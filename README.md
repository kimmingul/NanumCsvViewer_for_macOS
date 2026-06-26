# Nanum CSV Viewer for macOS

Nanum CSV Viewer is a Swift/AppKit macOS application for opening and inspecting very large CSV files. It is designed to load CSV files larger than 1 GB quickly, keep indexing work in the background, and render rows through a virtual table instead of materializing the whole file in memory.

## Features

- Automatic encoding detection for UTF-8, UTF-8 BOM, and CP949/EUC-KR
- CSV record byte-offset indexing
- Correct handling for quoted newlines, delimiters inside quotes, and escaped quotes
- Recovery for malformed first-row quotes that would otherwise hide following rows
- Virtual row rendering with `NSTableView`
- Background indexing progress
- Column statistics and type inference panel
- Expression-based advanced filters, column filters, and selected-cell value filters
- Advanced find with plain text, `regex:pattern`, `/pattern/`, and `fuzzy:term`
- Go to Row command for direct navigation by source row number
- Export of the current filtered/sorted view as CSV, Markdown, JSON, or HTML
- Persistent `.ncvidx` sidecar indexes for faster repeat opens
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
- Text-summary analytics for numeric distribution, date histogram, duplicate detection, group-by aggregation, and basic statistical tests
- Pivot Builder with field type tags, drag-and-drop plus selection/right-click field assignment, and an in-window Pivot Result panel for table and chart output; Values-only, Rows+Values, Columns+Values, and full Rows+Columns+Values layouts are supported.
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

## v1.6 User Workflows

- Open several CSV files at once from `File > Open...`; additional files open in native macOS tabs.
- Drag CSV files or CSV text onto the empty state or table area to open them quickly.
- Use `File > Open from Clipboard` to open copied CSV text, a copied file path, or a copied `file://` URL.
- Use the toolbar Find field with:
  - plain text for case-insensitive contains search
  - `regex:pattern` or `/pattern/` for regular expressions
  - `fuzzy:term` for ordered-character fuzzy matching
- Use `View > Save Current View` and `View > Restore Saved View` to keep a per-file view state.
- Use `View > Performance Dashboard` to inspect row counts, storage mode, indexing time, and throughput.
- Use `Analysis > Pivot Table` to open the Pivot Builder, then add fields by dragging, using the field buttons, or right-clicking a field. Values are measures with aggregation; Rows, Columns, and Filters are dimensions. Rows and Columns are optional, and the Pivot Table and Pivot Chart tabs update in the builder's large result panel.
- Use `File > Export as Markdown...`, `Export as JSON...`, or `Export as HTML...` to share the current filtered/sorted view with only visible columns.
- Expand the selected value bar with the chevron button when a selected cell contains multiline content.

## Roadmap Audit Status

The v1.6 release ships useful workflow coverage, but a post-release multi-review audit found that several GitHub v1 roadmap items are still partial rather than complete. Most analytics tools are still inspector/text summaries, while Pivot Table now opens an interactive builder with table and chart previews; column management does not yet include frozen columns; saved views are one per file rather than multiple named bookmarks; and UI customization controls for theme, font, and row density remain follow-up work.

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
- Persistent sidecar index writes are performed outside the load-completion path and skipped when the sidecar would be too large.
- Malformed first-row quote recovery is isolated to suspicious headers so valid quoted newline records still use the normal parser.
- Column equality and contains filters extract only the selected column instead of parsing full rows.
- Single-column sorting extracts only sort keys to reduce parsing cost.
- On macOS, the engine prefers an `mmap` byte source and falls back to a `pread`-based source when needed.

## License

Nanum CSV Viewer is available under the MIT License. See [LICENSE](LICENSE) for details.
