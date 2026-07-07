# Roadmap Status Audit

Last reviewed: 2026-07-04 KST (evening parity session)

## Windows Twin Parity (v1.15.0 기준, 2026-07-04)

The Windows twin (github.com/kimmingul/NanumCsvViewer) is at v1.15.0. Parity work status on macOS:

| Windows feature | macOS status |
| --- | --- |
| Grid scroll geometry correctness | **Fixed 2026-07-04** — deleted the parallel layout layer that ignored `intercellSpacing`; AppKit-native geometry, visually verified |
| Swift 6 language mode | **Done 2026-07-04** — full strict-concurrency migration, 215+ tests green |
| v1.13 extended statistics (descriptive/frequency/ANOVA/Shapiro-Wilk) | **Done 2026-07-04** — scipy-verified engine (`CsvExtendedStatistics`), Analysis menu entries |
| v1.13 manual column type override | **Done 2026-07-04** — header right-click ▸ Change Type, allow/validate/block classification, revert to auto |
| v1.13 SQLite (.db/.sqlite/.sqlite3) read-only open | **Done 2026-07-04** — system libsqlite3, table/view picker, tabs, temp-CSV bridge into the CSV engine |
| v1.8 type-aware filtering | **Done** — categorical/date header filter popovers, date ranges, plus numeric range filters via facets |
| v1.8 facet analysis panel | **Done 2026-07-04** — 232pt right dock (F6), 6-bin histograms / top-6 value bars, cross-filtering with own-filter exclusion, 2M row cap |
| v1.9 Excel multi-sheet open | **Done 2026-07-04** — pure-Swift xlsx/xlsm reader (internal ZIP + SAX XML), sheet picker, temp-CSV bridge; legacy .xls (BIFF) out of scope |
| v1.10–1.12 SPSS .sav / SAS .sas7bdat / field·value labels / declared types | **Scoped out 2026-07-04** — see "SPSS/SAS scope decision" below |
| v1.14 visualization menu, 7 statistical charts | **Done 2026-07-04** — Visualization menu, Swift Charts windows: histogram+KDE+SW badge, boxplot+ANOVA, scatter+OLS (density grid >20k pts), correlation heatmap, Q-Q, timeseries, Pareto; modeless, auto-close on document switch |
| v1.15 data quality review module | **Done 2026-07-04** — full-file profiler (sentinels, type validity, key uniqueness, ragged/duplicate rows, codebook, 0–100 score), Cmd+Shift+Q, Markdown/HTML/JSON export |

### SPSS/SAS scope decision (2026-07-04)

The Windows twin reads SPSS `.sav` via Curiosity.SPSS and SAS `.sas7bdat`/`.sas7bcat`
via a managed ReadStat port. No Swift equivalents exist, the repo has a
no-third-party-dependency constraint, and both formats (especially sas7bdat,
which is reverse-engineered) carry a correctness risk that outweighs the value
of a hand-rolled reader. Decision: **document as a known gap** rather than port.
The dependent features (field/value labels, declared-type matching,
Currency/Percent/Ordinal/Scientific declared types) are deferred with it.
If demand materializes, the plan is to wrap ReadStat as a C target in a
follow-up release rather than reimplementing the formats.

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

Done in the v1.8 line (2026-07-04):

- ~~Richer chart views~~ — the Visualization menu adds seven statistical chart windows (v1.14 parity).
- ~~Visible column checklist, persisted reorder, export order alignment~~ — View ▸ Columns checklist, per-file drag-reorder persistence, and export in on-screen visual order all shipped. **Frozen columns remain deferred** (triad adjudication: full Excel freeze panes re-introduce a parallel geometry layer + vertical-scroll drift against the freshly-stabilized grid geometry, for marginal value in a read-only viewer; the reorder mechanism now covers "keep identifiers leftmost"). Revisit as an explicit scoped milestone if lockstep freeze is still wanted.
- ~~Multiple named saved-view bookmarks with a picker + auto-restore~~ — shipped with legacy migration and integration tests.
- ~~Performance dashboard memory metrics~~ — process physical-memory footprint added; repeatable benchmark UI still pending.
- ~~Row-density controls~~ — Compact/Regular/Comfortable shipped; theme and font controls still pending.

- ~~Reduce analytics memory pressure~~ — done: analysis, charts, and pivot now stream the view (`forEachDisplayRow`/`forEachDataRow`) and project to used columns instead of materializing `currentDisplayRows`, cutting peak memory from O(rows × allColumns) to O(rows × few).

- ~~Clean up temporary files~~ — done: clipboard import files and Excel/SQLite temp-CSV bridge dirs are swept on launch with an age gate.
- ~~Prune per-file persistence maps~~ — done: saved views prune deleted files (parent-dir heuristic), column-order and pinned maps prune on write, hidden columns are a single global array.

- ~~Repeatable in-app benchmark runs~~ — done: View > Run Benchmark times read-only scans (full scan, search, distinct) and shows ms / rows / rows·s⁻¹, repeatable.
- ~~Theme and font controls~~ — done: View menu Appearance (System/Light/Dark) and Font Size (Small/Medium/Large, font-aware row height).
- ~~Export UX~~ — done: encoding choice (UTF-8 / BOM / CP949, CSV only), reveal-after-export, incremental progress, lossy-substitution warning.

All v1 roadmap follow-ups are complete. Deferred/scoped-out only: full Excel freeze panes, Mac App Store submission, SPSS/SAS, .xls BIFF.

## Release Guidance

- Keep the v1.6 GitHub roadmap issue open or split it into follow-up issues; do not mark the whole roadmap complete.
- Describe v1.6 as a workflow slice, not as completion of every v1 item.
- Treat graphical analytics, frozen columns, saved bookmarks, memory benchmark UI, and UI customization as the next high-priority roadmap gaps.
