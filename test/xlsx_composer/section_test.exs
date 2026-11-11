defmodule XLSXComposer.SectionTest do
  alias XLSXComposer.BorderDef
  alias XLSXComposer.BorderDef.Side
  alias XLSXComposer.CellDef
  alias XLSXComposer.ExcelCoords
  alias XLSXComposer.Section
  alias XLSXComposer.SectionCoords

  use ExUnit.Case, async: true

  setup_all do
    %{
      section_1_name: "section_1",
      c1_def:
        CellDef.new(%{
          content: "cell_1",
          bold: true
        }),
      c2_def:
        CellDef.new(%{
          content: "cell_2",
          bold: true
        }),
      c3_def:
        CellDef.new(%{
          content: "cell_3",
          bold: true
        }),
      c4_def:
        CellDef.new(%{
          content: "cell_4",
          bold: true
        })
    }
  end

  describe "section borders" do
    test "defaults are stored and no border leaves cells unchanged" do
      cell = CellDef.new(%{content: "value", border: [top: [style: :double]]})
      cells = %{SectionCoords.new() => cell}
      section = Section.new(%{name: "defaults", cells: cells})

      assert section.section_border === nil
      assert section.section_border_mode === :outline
      assert section.cells === cells
    end

    test "a single cell receives all cardinal outline sides" do
      coords = SectionCoords.new(2, 3)

      section =
        Section.new(%{
          name: "outline",
          cells: %{coords => CellDef.new(%{content: "value"})},
          section_border: BorderDef.new(%{preset: :thin})
        })

      assert CellDef.to_elixlsx_cell_def(section.cells[coords]) === [
               "value",
               {:border,
                [
                  left: [style: :thin],
                  right: [style: :thin],
                  top: [style: :thin],
                  bottom: [style: :thin]
                ]}
             ]
    end

    test "outline borders only outward sides and preserves other cell properties" do
      side = Side.new(%{style: :thin})
      diagonal = Side.new(%{style: :dotted})
      cell = CellDef.new(%{content: "value", bold: true, configuration: %{tag: :retained}})
      cells = for x <- 0..2, y <- 0..2, into: %{}, do: {SectionCoords.new(x, y), cell}

      section =
        Section.new(%{
          name: "grid",
          cells: cells,
          section_border: BorderDef.new(%{all: side, diagonal: diagonal, diagonal_up: true})
        })

      expected = %{
        {0, 0} => %BorderDef{left: side, top: side},
        {1, 0} => %BorderDef{top: side},
        {2, 0} => %BorderDef{right: side, top: side},
        {0, 1} => %BorderDef{left: side},
        {1, 1} => %BorderDef{},
        {2, 1} => %BorderDef{right: side},
        {0, 2} => %BorderDef{left: side, bottom: side},
        {1, 2} => %BorderDef{bottom: side},
        {2, 2} => %BorderDef{right: side, bottom: side}
      }

      for {{x, y}, border} <- expected do
        assert section.cells[SectionCoords.new(x, y)] === %CellDef{cell | border: border}
      end

      assert CellDef.to_elixlsx_cell_def(section.cells[SectionCoords.new(1, 1)]) === [
               "value",
               {:bold, true}
             ]
    end

    test "sparse outline uses occupied bounds and does not create missing cells" do
      side = Side.new(%{style: :double})

      cells = %{
        SectionCoords.new(2, 3) => CellDef.new(),
        SectionCoords.new(4, 3) => CellDef.new(),
        SectionCoords.new(3, 5) => CellDef.new()
      }

      section =
        Section.new(%{
          name: "sparse",
          cells: cells,
          top_left: ExcelCoords.new(5, 7),
          section_border: BorderDef.new(%{all: side})
        })

      assert Map.keys(section.cells) |> MapSet.new() === Map.keys(cells) |> MapSet.new()
      assert section.cells[SectionCoords.new(2, 3)].border === %BorderDef{left: side, top: side}
      assert section.cells[SectionCoords.new(4, 3)].border === %BorderDef{right: side, top: side}
      assert section.cells[SectionCoords.new(3, 5)].border === %BorderDef{bottom: side}
      assert section.bottom_right === ExcelCoords.new(9, 12)

      excel_cells = Section.to_excel_cells(section)
      assert excel_cells[ExcelCoords.new(7, 10)] === section.cells[SectionCoords.new(2, 3)]
      assert excel_cells[ExcelCoords.new(8, 12)] === section.cells[SectionCoords.new(3, 5)]
    end

    test "one row and one column receive both outward sides on their shared axis" do
      side = Side.new(%{style: :thin})
      border = BorderDef.new(%{all: side})

      row =
        Section.new(%{
          name: "row",
          cells: %{
            SectionCoords.new(2, 3) => CellDef.new(),
            SectionCoords.new(4, 3) => CellDef.new(),
            SectionCoords.new(6, 3) => CellDef.new()
          },
          section_border: border
        })

      assert row.cells[SectionCoords.new(2, 3)].border ===
               %BorderDef{left: side, top: side, bottom: side}

      assert row.cells[SectionCoords.new(4, 3)].border === %BorderDef{top: side, bottom: side}

      assert row.cells[SectionCoords.new(6, 3)].border ===
               %BorderDef{right: side, top: side, bottom: side}

      column =
        Section.new(%{
          name: "column",
          cells: %{
            SectionCoords.new(2, 3) => CellDef.new(),
            SectionCoords.new(2, 5) => CellDef.new(),
            SectionCoords.new(2, 7) => CellDef.new()
          },
          section_border: border
        })

      assert column.cells[SectionCoords.new(2, 3)].border ===
               %BorderDef{left: side, right: side, top: side}

      assert column.cells[SectionCoords.new(2, 5)].border === %BorderDef{left: side, right: side}

      assert column.cells[SectionCoords.new(2, 7)].border ===
               %BorderDef{left: side, right: side, bottom: side}
    end

    test "all mode adds every present side and diagonal flag to every cell" do
      border = %BorderDef{
        top: Side.new(%{style: :thin}),
        diagonal: Side.new(%{style: :dotted}),
        diagonal_up: true,
        diagonal_down: true
      }

      section =
        Section.new(%{
          name: "all",
          cells: %{
            SectionCoords.new() => CellDef.new(),
            SectionCoords.new(1, 1) => CellDef.new(),
            SectionCoords.new(2, 2) => CellDef.new()
          },
          section_border: border,
          section_border_mode: :all
        })

      assert section.section_border === border
      assert section.section_border_mode === :all

      for {_coords, cell} <- section.cells do
        assert cell.border === border

        assert CellDef.to_elixlsx_cell_def(cell) === [
                 {:border,
                  [
                    top: [style: :thin],
                    diagonal: [style: :dotted],
                    diagonal_up: true,
                    diagonal_down: true
                  ]}
               ]
      end
    end

    test "raw and typed per-cell sides take precedence over raw section sides" do
      top = Side.new(%{style: :double, color: "#cc3311"})
      diagonal = Side.new(%{style: :dotted})
      typed = %BorderDef{top: top, diagonal: diagonal, diagonal_up: true}

      raw = [
        top: [style: :double, color: "#cc3311"],
        diagonal: [style: :dotted],
        diagonal_up: true
      ]

      section_border = [top: [style: :thin], bottom: [style: :thin], diagonal_down: true]

      section =
        Section.new(%{
          name: "merge",
          cells: %{
            SectionCoords.new() => CellDef.new(%{border: typed}),
            SectionCoords.new(1, 1) => CellDef.new(%{border: raw})
          },
          section_border: section_border,
          section_border_mode: :all
        })

      assert section.section_border === section_border

      for {_coords, cell} <- section.cells do
        assert cell.border === %BorderDef{
                 top: top,
                 bottom: Side.new(%{style: :thin}),
                 diagonal: diagonal,
                 diagonal_up: true,
                 diagonal_down: true
               }
      end
    end

    test "outline preserves existing conflicting sides and diagonals" do
      top = Side.new(%{color: "#cc3311"})
      diagonal = Side.new(%{style: :double})
      coords = SectionCoords.new()

      section =
        Section.new(%{
          name: "merge outline",
          cells: %{coords => CellDef.new(%{border: %BorderDef{top: top, diagonal: diagonal}})},
          section_border: [top: [style: :thin], bottom: [style: :thin]]
        })

      assert section.cells[coords].border === %BorderDef{
               top: top,
               bottom: Side.new(%{style: :thin}),
               diagonal: diagonal
             }
    end

    test "omitted mode defaults to outline and empty sections remain empty" do
      border = BorderDef.new(%{preset: :thin})

      for args <- [%{}, %{section_border_mode: :outline}] do
        section = Section.new(Map.merge(%{name: "empty", section_border: border}, args))
        assert section.cells === %{}
        assert section.bottom_right === section.top_left
        assert section.section_border === border
        assert section.section_border_mode === :outline
      end

      assert Section.new(%{name: "empty all", section_border: border, section_border_mode: :all}).cells ===
               %{}
    end

    test "invalid or nil modes drop the section border and leave cells unchanged" do
      border = BorderDef.new(%{preset: :thin})
      cells = %{SectionCoords.new({0, 0}) => CellDef.new(%{content: "a"})}

      for mode <- [nil, :unknown, "all"] do
        section =
          Section.new(%{
            name: "invalid",
            cells: cells,
            section_border: border,
            section_border_mode: mode
          })

        assert section.cells === cells
        assert section.section_border === nil
        assert section.section_border_mode === nil
      end
    end
  end

  describe "new/1" do
    test "empty section sets the Section values and the same bottom_right as top_left" do
      top_left = ExcelCoords.new({1, 1})
      cells = %{}
      name = "section_1"

      assert %Section{
               name: name,
               top_left: top_left,
               cells: %{},
               bottom_right: top_left,
               section_border: nil,
               section_border_mode: :outline
             } ==
               Section.new(%{
                 name: name,
                 top_left: top_left,
                 cells: cells
               })
    end

    test "one row section sets the Section values", ctx do
      # -------------------
      # |XX|A2|XX|A4|XX|XX|
      # -------------------

      row_idx = 1
      top_left = ExcelCoords.new({1, row_idx})
      bottom_right = ExcelCoords.new({6, row_idx})
      name = "section_1"

      cells =
        %{
          SectionCoords.new(0, 0) => ctx.c1_def,
          SectionCoords.new(2, 0) => ctx.c2_def,
          SectionCoords.new(4, 0) => ctx.c3_def,
          SectionCoords.new(5, 0) => ctx.c4_def
        }

      assert %Section{
               name: name,
               top_left: top_left,
               cells: cells,
               bottom_right: bottom_right,
               section_border: nil,
               section_border_mode: :outline
             } ==
               Section.new(%{
                 name: name,
                 top_left: top_left,
                 cells: cells
               })
    end

    test "one column section sets the Section values", ctx do
      # ----------
      # |XX|A2|A3|
      # |B1|B2|B3|
      # |XX|C2|C3|
      # |D1|D2|D3|
      # |XX|E2|E3|
      # |XX|F2|F3|
      # ----------

      column_idx = 1
      top_left = ExcelCoords.new({column_idx, 1})
      bottom_right = ExcelCoords.new({column_idx, 6})
      name = "section_1"

      cells =
        %{
          SectionCoords.new(0, 0) => ctx.c1_def,
          SectionCoords.new(0, 2) => ctx.c2_def,
          SectionCoords.new(0, 4) => ctx.c3_def,
          SectionCoords.new(0, 5) => ctx.c4_def
        }

      assert %Section{
               name: name,
               top_left: top_left,
               cells: cells,
               bottom_right: bottom_right,
               section_border: nil,
               section_border_mode: :outline
             } ==
               Section.new(%{
                 name: name,
                 top_left: top_left,
                 cells: cells
               })
    end

    test "multiple cells, none of them in the right bottom corner, yet the value is calculated correctly",
         ctx do
      # ----------
      # |A1|A2|A3|
      # |B1|B2|XX|
      # |C1|XX|C3|
      # ----------

      top_left = ExcelCoords.new({1, 1})
      bottom_right = ExcelCoords.new({3, 3})
      name = "section_1"

      cells =
        %{
          SectionCoords.new(2, 1) => ctx.c1_def,
          SectionCoords.new(1, 2) => ctx.c2_def
        }

      assert %Section{
               name: name,
               top_left: top_left,
               cells: cells,
               bottom_right: bottom_right,
               section_border: nil,
               section_border_mode: :outline
             } ==
               Section.new(%{
                 name: name,
                 top_left: top_left,
                 cells: cells
               })
    end

    test "multiple cells, starts from C3", ctx do
      # ----------------
      # |A1|A2|A3|A4|A5|
      # |B1|B2|B3|B4|B5|
      # |C1|C2|C3|C4|C5|
      # |D1|D2|D3|D4|XX|
      # |E1|E2|E3|XX|E5|
      # ----------------

      top_left = ExcelCoords.new({3, 3})
      bottom_right = ExcelCoords.new({5, 5})
      name = "section_1"

      cells =
        %{
          SectionCoords.new(2, 1) => ctx.c1_def,
          SectionCoords.new(1, 2) => ctx.c2_def
        }

      assert %Section{
               name: name,
               top_left: top_left,
               cells: cells,
               bottom_right: bottom_right,
               section_border: nil,
               section_border_mode: :outline
             } ==
               Section.new(%{
                 name: name,
                 top_left: top_left,
                 cells: cells
               })
    end
  end

  describe "reduce_to_excel_cells/1" do
    test "empty section reduces empty excel_cells map", ctx do
      top_left = ExcelCoords.new({1, 1})
      cells = %{}

      assert %{
               name: ctx.section_1_name,
               top_left: top_left,
               cells: cells
             }
             |> Section.new()
             |> then(&[&1])
             |> Section.reduce_to_excel_cells() === %{}
    end

    test "one row scenario", ctx do
      # -------------------
      # |XX|A2|XX|A4|XX|XX|
      # -------------------

      top_left = ExcelCoords.new({1, 1})

      cells =
        %{
          SectionCoords.new(0, 0) => ctx.c1_def,
          SectionCoords.new(2, 0) => ctx.c2_def,
          SectionCoords.new(4, 0) => ctx.c3_def,
          SectionCoords.new(5, 0) => ctx.c4_def
        }

      assert %{
               name: ctx.section_1_name,
               top_left: top_left,
               cells: cells
             }
             |> Section.new()
             |> then(&[&1])
             |> Section.reduce_to_excel_cells() === %{
               ExcelCoords.new(1, 1) => ctx.c1_def,
               ExcelCoords.new(3, 1) => ctx.c2_def,
               ExcelCoords.new(5, 1) => ctx.c3_def,
               ExcelCoords.new(6, 1) => ctx.c4_def
             }
    end

    test "one column scenario", ctx do
      # ----------
      # |XX|A2|A3|
      # |B1|B2|B3|
      # |XX|C2|C3|
      # |D1|D2|D3|
      # |XX|E2|E3|
      # |XX|F2|F3|
      # ----------

      top_left = ExcelCoords.new({1, 1})

      cells =
        %{
          SectionCoords.new(0, 0) => ctx.c1_def,
          SectionCoords.new(0, 2) => ctx.c2_def,
          SectionCoords.new(0, 4) => ctx.c3_def,
          SectionCoords.new(0, 5) => ctx.c4_def
        }

      assert %{
               name: ctx.section_1_name,
               top_left: top_left,
               cells: cells
             }
             |> Section.new()
             |> then(&[&1])
             |> Section.reduce_to_excel_cells() === %{
               ExcelCoords.new(1, 1) => ctx.c1_def,
               ExcelCoords.new(1, 3) => ctx.c2_def,
               ExcelCoords.new(1, 5) => ctx.c3_def,
               ExcelCoords.new(1, 6) => ctx.c4_def
             }
    end

    test "multiple cells, none of them in the right bottom corner, yet the value is calculated correctly",
         ctx do
      # ----------
      # |A1|A2|A3|
      # |B1|B2|XX|
      # |C1|XX|C3|
      # ----------

      top_left = ExcelCoords.new({1, 1})

      cells =
        %{
          SectionCoords.new(2, 1) => ctx.c1_def,
          SectionCoords.new(1, 2) => ctx.c2_def
        }

      assert %{
               name: ctx.section_1_name,
               top_left: top_left,
               cells: cells
             }
             |> Section.new()
             |> then(&[&1])
             |> Section.reduce_to_excel_cells() === %{
               ExcelCoords.new(3, 2) => ctx.c1_def,
               ExcelCoords.new(2, 3) => ctx.c2_def
             }
    end

    test "multiple cells, starts from C3", ctx do
      # ----------------
      # |A1|A2|A3|A4|A5|
      # |B1|B2|B3|B4|B5|
      # |C1|C2|C3|C4|C5|
      # |D1|D2|D3|D4|XX|
      # |E1|E2|E3|XX|E5|
      # ----------------

      top_left = ExcelCoords.new({3, 3})

      cells =
        %{
          SectionCoords.new(2, 1) => ctx.c1_def,
          SectionCoords.new(1, 2) => ctx.c2_def
        }

      assert %{
               name: ctx.section_1_name,
               top_left: top_left,
               cells: cells
             }
             |> Section.new()
             |> then(&[&1])
             |> Section.reduce_to_excel_cells() === %{
               ExcelCoords.new(5, 4) => ctx.c1_def,
               ExcelCoords.new(4, 5) => ctx.c2_def
             }
    end
  end

  describe "below/1 and just_below/2" do
    test "below to an empty section" do
      top_left = ExcelCoords.new(1, 1)
      bottom_right = ExcelCoords.new(1, 1)

      # Correct just below point is one cell below the section above if the section above is not empty.
      correct_just_below = ExcelCoords.new(1, 1)

      assert correct_just_below ===
               %Section{
                 top_left: top_left,
                 bottom_right: bottom_right
               }
               |> Section.below()
    end

    test "below to an non-empty section" do
      top_left = ExcelCoords.new(1, 1)
      bottom_right = ExcelCoords.new(3, 3)

      # Correct just below point is one cell below the section above if the section above is not empty.
      correct_just_below = ExcelCoords.new(1, 4)

      assert correct_just_below ===
               %Section{
                 top_left: top_left,
                 bottom_right: bottom_right
               }
               |> Section.below()
    end

    test "below to an empty section with opts" do
      top_left = ExcelCoords.new(1, 1)
      bottom_right = ExcelCoords.new(1, 1)

      # Correct just below point is one cell below the section above if the section above is not empty.
      correct_just_below = ExcelCoords.new(3, 3)

      assert correct_just_below ===
               %Section{
                 top_left: top_left,
                 bottom_right: bottom_right
               }
               |> Section.below(move_x: 2, move_y: 2)
    end

    test "below to an non-empty section with opts" do
      top_left = ExcelCoords.new(1, 1)
      bottom_right = ExcelCoords.new(3, 3)

      # Correct just below point is one cell below the section above if the section above is not empty.
      correct_just_below = ExcelCoords.new(3, 6)

      assert correct_just_below ===
               %Section{
                 top_left: top_left,
                 bottom_right: bottom_right
               }
               |> Section.below(move_x: 2, move_y: 2)
    end
  end

  describe "to_the_right/1 and just_to_the_right/2" do
    test "to_the_right to an empty section" do
      top_left = ExcelCoords.new(1, 1)
      bottom_right = ExcelCoords.new(1, 1)
      correct_just_to_the_right = ExcelCoords.new(1, 1)

      assert correct_just_to_the_right ===
               %Section{
                 top_left: top_left,
                 bottom_right: bottom_right
               }
               |> Section.to_the_right()
    end

    test "to_the_right to an non-empty section" do
      top_left = ExcelCoords.new(1, 1)
      bottom_right = ExcelCoords.new(3, 3)
      correct_just_to_the_right = ExcelCoords.new(4, 1)

      assert correct_just_to_the_right ===
               %Section{
                 top_left: top_left,
                 bottom_right: bottom_right
               }
               |> Section.to_the_right()
    end

    test "to_the_right to an empty section with opts" do
      top_left = ExcelCoords.new(1, 1)
      bottom_right = ExcelCoords.new(1, 1)
      correct_just_to_the_right = ExcelCoords.new(3, 3)

      assert correct_just_to_the_right ===
               %Section{
                 top_left: top_left,
                 bottom_right: bottom_right
               }
               |> Section.to_the_right(move_x: 2, move_y: 2)
    end

    test "to_the_right to an non-empty section with opts" do
      top_left = ExcelCoords.new(1, 1)
      bottom_right = ExcelCoords.new(3, 3)
      correct_just_to_the_right = ExcelCoords.new(6, 3)

      assert correct_just_to_the_right ===
               %Section{
                 top_left: top_left,
                 bottom_right: bottom_right
               }
               |> Section.to_the_right(move_x: 2, move_y: 2)
    end
  end
end
