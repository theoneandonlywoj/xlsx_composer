defmodule XLSXComposer.SectionTest do
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

  describe "new/1" do
    test "empty section sets the Section values and the same bottom_right as top_left" do
      top_left = ExcelCoords.new({1, 1})
      cells = %{}
      name = "section_1"

      assert %Section{
               name: name,
               top_left: top_left,
               cells: %{},
               bottom_right: top_left
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
               bottom_right: bottom_right
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
               bottom_right: bottom_right
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
               bottom_right: bottom_right
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
               bottom_right: bottom_right
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
  end
end
