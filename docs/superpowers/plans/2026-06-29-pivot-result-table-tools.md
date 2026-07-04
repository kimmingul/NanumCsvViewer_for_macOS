# Pivot Result Table Tools Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add post-aggregation sort, filter, copy, and export tools to Pivot Builder result tables.

**Architecture:** Introduce a small pivot result display model that keeps each section's raw headers and rows plus table-only sort/filter state, then have the AppKit preview sections render the model's visible rows. Copy and export use the same visible display model so the user gets exactly what they are viewing.

**Tech Stack:** Swift 6.3 package, AppKit `NSTableView`, `NSSavePanel`, `NSPasteboard`, existing `SortHeaderCell`, and XCTest.

## Global Constraints

- No new dependencies.
- Keep CsvCore pivot aggregation behavior unchanged.
- Result filters are post-aggregation display filters, distinct from existing source-data pivot filters.
- Sorting numeric-looking cells must sort numerically, not lexicographically.
- Copy/export must operate on current visible rows after result sort/filter.

---

### Task 1: Result Display Model

**Files:**
- Modify: `NanumCsvViewerMac/Sources/NanumCsvViewerMac/PivotBuilderModel.swift`
- Test: `NanumCsvViewerMac/Tests/NanumCsvViewerMacTests/PivotBuilderTests.swift`

**Interfaces:**
- Produces: `PivotResultTableState`, `PivotResultTableModel`, `PivotResultExportFormat`
- Produces: `sort(column:ascending:)`, `setFilter(column:query:)`, `visibleRows`, `exportString(format:)`

- [ ] Write failing tests for numeric sorting, filtering, TSV copy, and CSV export.
- [ ] Run `swift test --filter PivotBuilderTests` and confirm the new tests fail because the types do not exist.
- [ ] Implement the minimal model and formatting helpers.
- [ ] Run `swift test --filter PivotBuilderTests` and confirm the model tests pass.

### Task 2: Pivot Builder UI Integration

**Files:**
- Modify: `NanumCsvViewerMac/Sources/NanumCsvViewerMac/PivotBuilderWindowController.swift`
- Test: `NanumCsvViewerMac/Tests/NanumCsvViewerMacTests/PivotBuilderTests.swift`

**Interfaces:**
- Consumes: `PivotResultTableModel`
- Produces: section table sort/filter controls and testing accessors.

- [ ] Add failing controller tests for section sort/filter and copy/export strings.
- [ ] Run `swift test --filter PivotBuilderTests` and confirm expected failures.
- [ ] Store a table model in each preview section, wire header clicks and a compact result filter field to update visible rows.
- [ ] Add Copy and Export controls to the Pivot Result header.
- [ ] Run `swift test --filter PivotBuilderTests`.

### Task 3: Verification

**Files:**
- Test only.

- [ ] Run `swift test --filter PivotBuilderTests`.
- [ ] Run `swift test`.
- [ ] Report changed files, passing commands, and any remaining risk.
