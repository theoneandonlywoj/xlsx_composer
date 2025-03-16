defmodule XLSXComposer.SectionTest do
  alias XLSXComposer.CellDef
  alias XLSXComposer.ExcelCoords
  alias XLSXComposer.Section
  alias XLSXComposer.SectionCoords

  use ExUnit.Case, async: true

  doctest XLSXComposer.Section

  describe "new/1" do
    test "empty section sets the Section values and the same bottom_right as top_left" do
      top_left = ExcelCoords.new({1, 1})
      cells = %{}
      name = "section_1"

      assert %Section{
               name: name,
               top_left: top_left,
               cells: cells,
               bottom_right: top_left
             } ==
               Section.new(%{
                 name: name,
                 top_left: top_left,
                 cells: %{}
               })
    end

    test "one row section sets the Section values" do
      # -------------------
      # |XX|A2|XX|A4|XX|XX|
      # -------------------

      row_idx = 1
      top_left = ExcelCoords.new({1, row_idx})
      bottom_right = ExcelCoords.new({6, row_idx})
      name = "section_1"

      cells =
        %{
          SectionCoords.new(0, 0) =>
            CellDef.new(%{
              content: "cell_1",
              bold: true
            }),
          SectionCoords.new(2, 0) =>
            CellDef.new(%{
              content: "cell_2",
              bold: true
            }),
          SectionCoords.new(4, 0) =>
            CellDef.new(%{
              content: "cell_3",
              bold: true
            }),
          SectionCoords.new(5, 0) =>
            CellDef.new(%{
              content: "cell_4",
              bold: true
            })
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

    test "one column section sets the Section values" do
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
          SectionCoords.new(0, 0) =>
            CellDef.new(%{
              content: "cell_1",
              bold: true
            }),
          SectionCoords.new(0, 2) =>
            CellDef.new(%{
              content: "cell_2",
              bold: true
            }),
          SectionCoords.new(0, 4) =>
            CellDef.new(%{
              content: "cell_3",
              bold: true
            }),
          SectionCoords.new(0, 5) =>
            CellDef.new(%{
              content: "cell_4",
              bold: true
            })
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

    test "multiple cells, none of them in the right bottom corner, yet the value is calculated correctly" do
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
          SectionCoords.new(2, 1) =>
            CellDef.new(%{
              content: "cell_1",
              bold: true
            }),
          SectionCoords.new(1, 2) =>
            CellDef.new(%{
              content: "cell_2",
              bold: true
            })
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

    test "multiple cells, starts from C3" do
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
          SectionCoords.new(2, 1) =>
            CellDef.new(%{
              content: "cell_1",
              bold: true
            }),
          SectionCoords.new(1, 2) =>
            CellDef.new(%{
              content: "cell_2",
              bold: true
            })
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
end
