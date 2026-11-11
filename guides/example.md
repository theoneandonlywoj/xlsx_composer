# Example

A two-row invoice table built from two composed sections: a header row and a
data row placed directly below it. The block below is evaluated by the test
suite, so it always matches the library.

<!-- example:build -->

```elixir
alias XLSXComposer.BorderDef
alias XLSXComposer.BorderDef.Side
alias XLSXComposer.CellDef
alias XLSXComposer.ExcelCoords
alias XLSXComposer.Section
alias XLSXComposer.SectionCoords
alias XLSXComposer.Sheet

header_style = %{bold: true, color: "#FFFFFF", bg_color: "#1F4E79"}

# Section 1: the header row, every side of every cell bordered (:all).
header =
  Section.new(%{
    name: "header",
    top_left: ExcelCoords.new(2, 2),
    section_border: BorderDef.new(%{preset: :thin}),
    section_border_mode: :all,
    cells: %{
      SectionCoords.new(0, 0) => CellDef.new(Map.put(header_style, :content, "Ship date")),
      SectionCoords.new(1, 0) =>
        CellDef.new(Map.merge(header_style, %{content: "Amount (USD)", align_horizontal: :right}))
    }
  })

# Section 2: the data row, placed directly below the header; only its outline is bordered.
body =
  Section.new(%{
    name: "body",
    top_left: Section.below(header),
    section_border: BorderDef.new(%{preset: :thin}),
    cells: %{
      SectionCoords.new(0, 0) =>
        CellDef.new(%{content: {{2024, 7, 4}, {0, 0, 0}}, num_format: "mm/dd/yyyy"}),
      SectionCoords.new(1, 0) =>
        CellDef.new(%{
          content: 1234.5678,
          num_format: "#,##0.00",
          bg_color: "#FFF2CC",
          border: BorderDef.new(%{bottom: Side.new(%{style: :double, color: "#CC3311"})})
        })
    }
  })

sheet = Sheet.new(%{name: "Invoice", sections: [header, body]})
```

Write it with `XLSXComposer.write/2`:

<!-- example:write -->

```elixir
{:ok, _path} = XLSXComposer.write([sheet], "invoice.xlsx")
```

## What you get

- Header at B2:C2, with a thin border on every side of both cells (`:all` mode).
- Body at B3:C3, placed by `Section.below(header)`, so it follows the header
  wherever the header moves.
- B3 shows `07/04/2024`.
- C3 shows `1,234.57` on light yellow.
- Excel shows `/`, `,` and `.` using the reader's locale; en-US shows
  `07/04/2024` and `1,234.57`.
- The body has a thin outline, except C3's bottom, which keeps its own double red
  line: cell sides win over the section border.

Each section has its own 0-based `SectionCoords`, so both sections use
`SectionCoords.new(0, 0)` and `SectionCoords.new(1, 0)`; `Sheet.new/1` flattens
the sections into Excel coordinates.

## US formats

- Use `num_format: "mm/dd/yyyy"` alone. `datetime: true` and `yyyymmdd: true`
  override `num_format` with ISO formats. `num_format`
  counts as a date format only if it contains `"yy"` (case-sensitive).
- Date content must be an Erlang tuple `{{y, m, d}, {h, m, s}}` or an integer of
  unix seconds. Convert a `NaiveDateTime` with `NaiveDateTime.to_erl/1` and a
  `Date` with `{Date.to_erl(date), {0, 0, 0}}`. Passing the structs raises at
  write time.
- The custom format string (month/day/year order) is stored in the file, though
  Excel may show the `/` separator using the reader's locale.
- `num_format: "#,##0.00"` gives a thousands separator and two decimals; Excel
  shows `,` and `.` using the reader's locale (en-US shows `1,234.57`).
