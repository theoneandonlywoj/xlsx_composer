defmodule XLSXComposer.Section do
  @moduledoc """
  #{__MODULE__} allows to group cells into units that we can reason and test on that level.

  WARNING! : limit number of Sections otherwise the process of the checks might hurt your performance!
  Soon, implementation of checking of Sections overlap will have to be done so use Section carefully.
  """
  alias XLSXComposer.CellDef
  alias XLSXComposer.ExcelCoords
  alias XLSXComposer.Section
  alias XLSXComposer.SectionCoords

  @type t() :: %Section{
          name: name_t(),
          cells: CellDef.section_cells(),
          top_left: ExcelCoords.t(),
          bottom_right: ExcelCoords.t()
        }

  @type new_attrs() :: %{
          name: name_t(),
          top_left: ExcelCoords.t(),
          cells: CellDef.section_cells()
        }

  @type name_t() :: String.t()

  @type area_t() :: {ExcelCoords.t(), ExcelCoords.t()}

  defstruct name: "",
            cells: %{},
            top_left: ExcelCoords.new(),
            bottom_right: ExcelCoords.new()

  @spec new(new_attrs()) :: Section.t()
  def new(args) do
    top_left = args[:top_left] || ExcelCoords.new()
    cells = args[:cells] || %{}

    %Section{
      name: args.name,
      cells: cells,
      top_left: top_left,
      bottom_right: calculate_bottom_right(top_left, cells)
    }
  end

  @spec calculate_bottom_right(ExcelCoords.t(), CellDef.section_cells()) :: ExcelCoords.t()
  defp calculate_bottom_right(%ExcelCoords{} = top_left, section_cells) do
    section_cells
    # Pick all SectionCoords
    |> Map.keys()
    # Get max x and max y, which correspond to the bottom corner of the section
    |> Enum.reduce(
      # We start from {0, 0}
      {0, 0},
      fn section_cord, {bottom_right_x, bottom_right_y} ->
        new_bottom_right_x = pick_higher_int(bottom_right_x, section_cord.x)
        new_bottom_right_y = pick_higher_int(bottom_right_y, section_cord.y)

        {new_bottom_right_x, new_bottom_right_y}
      end
    )
    |> SectionCoords.new()
    |> then(&ExcelCoords.displace(top_left, &1))
  end

  @spec overlap?(Section.t(), Section.t()) :: any()
  def overlap?(%Section{} = section_1, %Section{} = section_2) do
    # section 2 top left inside section 1
    # = (section 2 top left x between section 1 top left x and section 1 bottom right x)
    # and (section 2 top left y between section 1 top left y and section 1 bottom right y)
    # section 1 top left inside section 2
    # = (section 1 top left x between section 2 top left x and section 2 bottom right x)
    # and (section1 top left y between section 2 top left y and section 2 bottom right y)
    (section_2.top_left.x >= section_1.top_left.x and
       section_2.top_left.x <= section_1.bottom_right.x and
       section_2.top_left.y >= section_1.top_left.y and
       section_2.top_left.y <= section_1.bottom_right.y) or
      (section_1.top_left.x >= section_2.top_left.x and
         section_1.top_left.x <= section_2.bottom_right.x and
         section_1.top_left.y >= section_2.top_left.y and
         section_1.top_left.y <= section_2.bottom_right.y)
  end

  @spec to_excel_cells(Section.t()) :: CellDef.excel_cells()
  def to_excel_cells(%Section{cells: cells, top_left: top_left} = _section) do
    cells
    |> Enum.map(fn {cell_section_coords, cell_def} ->
      {ExcelCoords.displace(top_left, cell_section_coords), cell_def}
    end)
    |> Map.new()
  end

  @spec pick_higher_int(non_neg_integer(), non_neg_integer()) :: non_neg_integer()
  defp pick_higher_int(int_1, int_2) when int_1 > int_2, do: int_1
  defp pick_higher_int(int_1, int_2) when int_1 <= int_2, do: int_2
end
