# Release Notes

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
