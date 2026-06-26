# Pivot Builder Design

## Goal

Build an Excel-like Pivot Builder for Nanum CSV Viewer before the v2 AI work. The feature must make pivot tables and pivot charts understandable without requiring the user to infer behavior from the Analysis menu.

## Scope

- Open Pivot Builder from `Analysis > Pivot Table`.
- Present the builder in a separate native AppKit window.
- Use a drag-and-drop field list from the first implementation.
- Compute pivots from the current filtered view, matching existing analysis behavior.
- Reuse the existing `CsvCore` pivot calculation and export behavior where possible.
- Keep the feature entirely non-AI.

## User Experience

The window has four primary regions:

1. Field list: all CSV columns with type hints where available.
2. Drop zones: `Rows`, `Columns`, `Values`, and `Filters`.
3. Result preview: a real grid-style pivot table, not plain text.
4. Chart preview: a chart derived from the same pivot result.

Users can drag columns from the field list into zones. They can also remove fields from zones and change the aggregation function for value fields. The first version supports one value field and one aggregation function at a time, because the current core model is single-value. The UI should make that limitation explicit through enabled controls rather than error text.

## Pivot Table Behavior

- `Rows` accepts one or more categorical fields.
- `Columns` accepts one or more categorical fields.
- `Values` accepts exactly one field.
- The value aggregation supports the existing functions: `Count`, `Sum`, `Mean`, `Median`, `Min`, `Max`, `Unique Count`, and `Std`.
- Empty cells render as `0`, matching the existing core result.
- Result rows and columns preserve the existing sorted-key behavior.
- The preview uses an `NSTableView` with dynamic columns.

## Pivot Chart Behavior

The first chart version should cover the most useful pivot shape:

- Bar chart for pivot tables with one row dimension and one or more column groups.
- Series names come from pivot column keys.
- X-axis categories come from pivot row keys.
- Y-axis values come from pivot cell values.

If the selected layout is too complex for the first chart renderer, the table still renders and the chart pane shows a concise unsupported-layout state. This is acceptable for multi-row or deeply nested pivots in the first version.

The chart can be implemented with a custom AppKit view if Swift Charts integration would add too much framework complexity to the existing AppKit executable target. The visible result must still be a real chart, not a text summary.

## Error Handling

- Opening Pivot Builder without a loaded, indexed document is disabled.
- Empty required zones show an inline empty state in the preview.
- Invalid field placement should be prevented by drop validation when possible.
- Long-running recompute work should use the existing busy/progress patterns or equivalent cancellation-safe dispatch.
- Large result sets should remain scrollable and avoid creating unbounded label views.

## Testing

Core tests should continue covering pivot aggregation and CSV export. App tests should cover:

- The builder opens from a document.
- Drag/drop or programmatic equivalent assigns row, column, and value fields.
- Changing aggregation recomputes the preview.
- The table preview exposes expected headers and cell values.
- The chart view receives the same pivot result and reports renderable series for simple layouts.

## Out Of Scope

- AI suggestions or natural-language pivot creation.
- Multiple simultaneous value fields.
- Calculated fields.
- Persisted pivot layouts.
- Image export for charts.
- Full Excel parity.

## Open Decisions Resolved

- The Pivot Builder is a separate window.
- Drag-and-drop field list is included in the initial implementation.
- The feature belongs to v1 non-AI work, not v2 AI Assistant work.
