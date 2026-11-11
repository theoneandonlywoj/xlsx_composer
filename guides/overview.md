# Overview

XLSXComposer is a declarative builder for `.xlsx` files on top of Elixlsx. You
describe cells as plain structs, group them into relocatable sections, collect
the sections into sheets, and write the result in one call. Rows are built once
from a map of cells instead of being edited cell by cell.

## Installation

Add `:xlsx_composer` to your dependencies in `mix.exs`; see Hex for the current
version.

## Pipeline

```text
CellDef -> Section -> Sheet -> XLSXComposer.write/2 or XLSXComposer.to_workbook/1 -> Elixlsx
```

- `XLSXComposer.CellDef`: one cell's content and style.
- `XLSXComposer.Section`: cells keyed by `XLSXComposer.SectionCoords` (0-based),
  placed at an `XLSXComposer.ExcelCoords` `top_left` (1-based, Excel-style).
- `XLSXComposer.Sheet`: a named sheet built from sections.
- `XLSXComposer.write/2` writes sheets to a file; `XLSXComposer.to_workbook/1`
  returns the `Elixlsx.Workbook` struct for further changes.

## Guides

- [Components](components.md): every building block and its options, plus gotchas.
- [Example](example.md): a tested two-section table with US date and number formats.
- [Why XLSXComposer vs Elixlsx](why-xlsx-composer.md): when to use which.
