# Why XLSXComposer vs Elixlsx

XLSXComposer builds on Elixlsx; it does not replace it. It changes how you
describe a sheet and how the rows are built.

| | Elixlsx, cell by cell | Elixlsx, hand-built rows | XLSXComposer |
|---|---|---|---|
| Building rows | `Elixlsx.Sheet.set_cell/4` walks, pads and rebuilds the row lists on every call | You write the row and column padding | Cells live in a map; each row is built once |
| Cost of many cells | Roughly O(cells x (rows + columns)) | No rebuilds, but the padding is yours | Each row built once; a wide dense row still costs O(cells x columns) for that row |
| Moving a block | Recompute every coordinate | Recompute every coordinate | Change one section's `top_left` |
| Borders | Keyword lists per cell | Keyword lists per cell | Typed `XLSXComposer.BorderDef` with presets and section outlines |
| Testing | Inspect nested lists | Inspect nested lists | Pattern-match plain structs; test a section on its own |

## What you gain

- Sections are relocatable units with their own coordinates and testable output.
- Typed borders with presets, precedence rules and section outlines.
- Plain structs you can pattern-match in tests.

## When to use plain Elixlsx

XLSXComposer does not expose column widths, merged cells or frozen panes. Call
`XLSXComposer.to_workbook/1` and edit the returned `Elixlsx.Sheet` structs, for
example with `Elixlsx.Sheet.set_col_width/3`, then write with
`Elixlsx.write_to/2`.
