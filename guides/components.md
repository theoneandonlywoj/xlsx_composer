# Components

## XLSXComposer.CellDef

One cell: `content` plus optional style. Build it with `XLSXComposer.CellDef.new/1`.

| Option | Meaning |
|---|---|
| `content` | Value written to the cell (string, number, date tuple, ...). Required. |
| `wrap_text` | Wrap long text. |
| `font` | Font name. |
| `align_vertical` | `:top`, `:bottom`, `:center`. |
| `align_horizontal` | `:left`, `:right`, `:center`, `:justify`, `:general`, `:fill`. |
| `bold`, `italic`, `underline`, `strike` | Font style flags. |
| `size` | Font size. |
| `color`, `bg_color` | Font and fill color, `"#RRGGBB"`. |
| `num_format` | Excel number format, e.g. `"#,##0.00"` or `"mm/dd/yyyy"`; counts as a date format only if it contains `"yy"` (case-sensitive). |
| `datetime`, `yyyymmdd` | Truthy flags that override `num_format` with ISO date formats. |
| `border` | An `XLSXComposer.BorderDef`. |
| `configuration` | Your own map for tagging cells; not written to the file. |

## XLSXComposer.BorderDef and XLSXComposer.BorderDef.Side

A typed border; each side is a `XLSXComposer.BorderDef.Side` with `style` and `color`.

- `preset:` fills the four cardinal sides.
- `all:` fills the four cardinal sides and takes precedence over `preset:`.
- Explicit sides (`left`, `right`, `top`, `bottom`) take precedence over `all:`.
- Diagonals are explicit only.
- Styles: `:thin`, `:medium`, `:thick`, `:dotted`, `:dashed`, `:double`,
  `:dash_dot`, `:dash_dot_dot`.

## XLSXComposer.Section

A named group of cells keyed by `XLSXComposer.SectionCoords`, placed at a
`top_left` `XLSXComposer.ExcelCoords`.

- `section_border` with `section_border_mode: :outline` (default) adds the
  outward-facing sides of the bounding box of the occupied cells (a gap inside
  it gets no border).
- `section_border_mode: :all` adds every supplied side to every cell.
- Cell sides always win over the section border.
- Layout: `XLSXComposer.Section.below/2` and `XLSXComposer.Section.to_the_right/2`
  return the `top_left` for the next section, so sections can be chained and moved
  together. A section built with `XLSXComposer.Section.new/1` and no cells takes
  no space: the next section starts at its `top_left`.

## XLSXComposer.SectionCoords and XLSXComposer.ExcelCoords

- `XLSXComposer.SectionCoords`: 0-based `x` (column) and `y` (row) offsets from
  the section's `top_left`.
- `XLSXComposer.ExcelCoords`: 1-based column and row (A1 is `ExcelCoords.new(1, 1)`);
  `pretty` holds the `"A1"`-style address.

## XLSXComposer.Sheet

A named sheet built with `XLSXComposer.Sheet.new/1` from a list of sections.
`XLSXComposer.Sheet.to_elixlsx_sheet/1` converts it to an `Elixlsx.Sheet`.

## XLSXComposer

- `XLSXComposer.write/2` writes sheets to a path and returns Elixlsx's result.
- `XLSXComposer.to_workbook/1` returns the `Elixlsx.Workbook` without writing it.

## Gotchas

| Topic | Rule |
|---|---|
| Colors | Always `"#RRGGBB"`. |
| Empty cells | Every `CellDef` needs content: a `nil`-content cell, styled or not, crashes at write time. Use `content: ""` for an empty (styled) cell. |
| `false` content | `XLSXComposer.CellDef.new/1` turns `content: false` into `nil`, so it crashes too; write `"FALSE"`/`0`, or use `XLSXComposer.CellDef.set_content/2`, which keeps `false` as a boolean cell. |
| Sections per sheet | `Sheet.new/1` needs at least one section. |
| Sheet name | Non-empty, at most 31 characters, none of `: \ / ? * [ ]`. Excel also rejects duplicate sheet names and names starting or ending with `'`; Elixlsx does not check these. |
| Duplicate section names | Later sections with the same name are dropped (first wins), though a dropped section still extends the sheet's row count. |
| Overlapping cells | Nothing checks overlap; the later section wins silently. |
| Rows | Excel rows start at 1. |
