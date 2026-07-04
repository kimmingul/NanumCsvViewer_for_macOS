# Roadmap Status Audit

Last reviewed: 2026-07-04 KST

## Windows Twin Parity (v1.15.0 기준, 2026-07-04)

The Windows twin (github.com/kimmingul/NanumCsvViewer) is at v1.15.0. Parity work status on macOS:

| Windows feature | macOS status |
| --- | --- |
| Grid scroll geometry correctness | **Fixed 2026-07-04** — deleted the parallel layout layer that ignored `intercellSpacing`; AppKit-native geometry, visually verified |
| Swift 6 language mode | **Done 2026-07-04** — full strict-concurrency migration, 215+ tests green |
| v1.13 extended statistics (descriptive/frequency/ANOVA/Shapiro-Wilk) | **Done 2026-07-04** — scipy-verified engine (`CsvExtendedStatistics`), Analysis menu entries |
| v1.13 manual column type override | **Done 2026-07-04** — header right-click ▸ Change Type, allow/validate/block classification, revert to auto |
| v1.13 SQLite (.db/.sqlite/.sqlite3) read-only open | **Done 2026-07-04** — system libsqlite3, table/view picker, tabs, temp-CSV bridge into the CSV engine |
| v1.8 type-aware filtering | Largely present (categorical/date header filter popovers, date ranges); facet panel UI pending |
| v1.8 facet analysis panel | Pending |
| v1.9 Excel/SAS multi-sheet open | Pending (needs pure-Swift xlsx reader; SAS formats are a larger effort) |
| v1.10–1.12 SPSS .sav / SAS labels / declared types / Currency·Percent·Ordinal·Scientific types | Pending |
| v1.14 visualization menu, 7 statistical charts | Pending (Swift Charts foundation exists in pivot charts) |
| v1.15 data quality review module | Pending |

This audit checks whether the GitHub v1 roadmap, including the v1.6 issue list, matches the current implementation. The short answer is: v1.6 is usable and includes several workflow improvements, but the full v1 roadmap should not be treated as complete yet.

## Review Inputs

- Codex code-reviewer subagent: completed, with focused findings on roadmap gaps and regression coverage.
- Codex architect subagent: completed, with findings on release-scope mismatch and UX architecture gaps.
- Claude CLI: completed, with an issue-by-issue roadmap audit.
- Gemini CLI: attempted, but the local CLI rejected this client tier and suggested Antigravity; no usable audit output was available.
- Grok CLI: attempted, but the local CLI reached its turn limit without usable audit output.

## Current Status

| Area | Status | Notes |
| --- | --- | --- |
| Large-file opening, indexing, virtual table | Implemented | Core open/index/render flow is covered by tests and benchmark tooling. |
| Encoding and CSV parsing robustness | Implemented | UTF-8/BOM/CP949 handling and quoted newline cases are covered. |
| Filtering, sorting, find, Go to Row | Mostly implemented | Compact comparison filters such as `age>65` and `age=65` were fixed after the audit. |
| Export current view | Mostly implemented | CSV/Markdown/JSON/HTML exist. JSON duplicate headers and streaming export were fixed after the audit. Encoding selection and open-after-export remain pending. |
| Column management | Partial | Hide/show exists. Frozen columns, a richer checklist UI, and persisted reorder remain pending. |
| Multi-file workflow | Implemented | Native macOS tabs and multi-open workflows exist. |
| Saved views/bookmarks | Partial | One per-file saved view exists. Multiple named bookmarks, a picker, auto-restore, and stronger UI tests remain pending. |
| Advanced search | Implemented | Plain text, regex, slash-regex, fuzzy, and column-scoped search exist. Regex matching now compiles the pattern once per search. |
| Analytics and statistics | Partial | Text-summary tools exist for distribution, date histogram, duplicates, group-by, and statistical tests. Pivot now has an interactive builder with an in-window table/chart result panel, including Values-only and single-axis layouts. Broader graphical chart views are pending. Statistical p-values and confidence intervals were corrected after the audit. |
| Performance dashboard | Partial | Row count, file size, storage, indexing time, and throughput are shown. Memory metrics and repeatable benchmark UI remain pending. |
| UI customization | Partial | System light/dark appearance works. Custom themes, font controls, and row density controls remain pending. |
| Clipboard and drag/drop import | Implemented | Clipboard CSV/path/URL import and drag/drop import exist. Temp-file lifecycle cleanup can be improved. |

## Fixes Applied After Audit

- Corrected statistical p-values and 95% confidence intervals to use Student t and gamma-survival calculations instead of normal approximations.
- Added regression tests for independent t-test, paired t-test, and chi-square p-value calculations.
- Fixed filter expression routing so compact comparisons such as `age>65`, `age=65`, and `score<=10` are parsed as expressions.
- Added AppKit regression tests for expression routing.
- Fixed JSON export to preserve duplicate headers using stable keys such as `value` and `value (2)`.
- Changed JSON export to stream objects row by row instead of materializing the whole export array.
- Refactored regex search to compile the regular expression once per search request instead of once per cell.
- Expanded Pivot Builder layouts so Values-only, Rows+Values, Columns+Values, and Rows+Columns+Values previews work.
- Moved Pivot Builder preview aggregation off the main thread and added cancellation for stale pivot aggregation work.
- Reworked the Pivot Builder into a left-side setup panel and a larger in-window result panel for Pivot Table and Pivot Chart tabs.

## Follow-Up Work

1. Add richer chart views for numeric distributions, date histograms, group-by outputs, and advanced pivot layouts.
2. Finish column management with frozen columns, a visible column checklist workflow, persisted reorder, and export order alignment.
3. Expand saved views into multiple named bookmarks with a picker, auto-restore behavior, and integration tests.
4. Upgrade the performance dashboard with memory metrics and repeatable benchmark runs.
5. Add theme, font, and row-density controls beyond system light/dark mode.
6. Reduce analytics memory pressure by streaming or sampling intentionally instead of materializing `currentDisplayRows` for every analysis.
7. Improve export UX with encoding selection, open-after-export, selected-column control, and large JSON progress behavior.
8. Clean up temporary files created by clipboard quick import.

## Release Guidance

- Keep the v1.6 GitHub roadmap issue open or split it into follow-up issues; do not mark the whole roadmap complete.
- Describe v1.6 as a workflow slice, not as completion of every v1 item.
- Treat graphical analytics, frozen columns, saved bookmarks, memory benchmark UI, and UI customization as the next high-priority roadmap gaps.
