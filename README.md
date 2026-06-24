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
- Go to Row command for direct navigation by source row number
- Export of the current filtered/sorted view
- Persistent `.ncvidx` sidecar indexes for faster repeat opens
- Fast single-column filter and sort paths
- Shift-click multi-column sorting
- Column hide/show controls, selected value bar, filter bar, and Inspector panel
- Bounded one-line table previews for long multiline/XML cells, with full values preserved in the inspector and copy actions
- Numeric distribution, date histogram, duplicate detection, group-by aggregation, pivot table, and basic statistical analysis tools
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
  Tests/CsvCoreTests/     # CSV parser, index, filter, and sort tests
  Tests/NanumCsvViewerMacTests/
                         # AppKit grid materialization regression tests
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
