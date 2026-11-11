defmodule XLSXComposer.Section do
  @moduledoc """
  #{__MODULE__} allows to group cells into units that we can reason and test on that level.

  WARNING! : limit number of Sections otherwise the process of the checks might hurt your performance!
  Soon, implementation of checking of Sections overlap will have to be done so use Section carefully.

  `section_border` adds outward-facing cardinal sides in the default `:outline`
  mode, or every supplied side in `:all` mode. Existing cell sides take precedence.
  """
  alias XLSXComposer.BorderDef
  alias XLSXComposer.CellDef
  alias XLSXComposer.ExcelCoords
  alias XLSXComposer.Section
  alias XLSXComposer.SectionCoords

  @type t() :: %Section{
          name: name_t(),
          cells: CellDef.section_cells(),
          top_left: ExcelCoords.t(),
          bottom_right: ExcelCoords.t(),
          section_border: BorderDef.t() | keyword() | nil,
          section_border_mode: :outline | :all
        }

  @type new_attrs() :: %{
          optional(:section_border) => BorderDef.t() | keyword() | nil,
          optional(:section_border_mode) => :outline | :all,
          :name => name_t(),
          :top_left => ExcelCoords.t(),
          :cells => CellDef.section_cells()
        }

  @type name_t() :: String.t()

  @type area_t() :: {ExcelCoords.t(), ExcelCoords.t()}

  defstruct name: "",
            cells: %{},
            top_left: ExcelCoords.new(),
            bottom_right: ExcelCoords.new(),
            section_border: nil,
            section_border_mode: :outline

  @doc "Creates a section and applies its border before calculating its extent."
  @spec new(new_attrs()) :: Section.t()
  def new(args) do
    top_left = args[:top_left] || ExcelCoords.new()
    section_border = args[:section_border]
    section_border_mode = if args[:section_border_mode] == :all, do: :all, else: :outline

    cells =
      (args[:cells] || %{})
      |> apply_section_border(section_border, section_border_mode)

    %Section{
      name: args.name,
      cells: cells,
      top_left: top_left,
      bottom_right: calculate_bottom_right(top_left, cells),
      section_border: section_border,
      section_border_mode: section_border_mode
    }
  end

  defp apply_section_border(cells, nil, _mode), do: cells
  defp apply_section_border(cells, _border, _mode) when cells == %{}, do: cells

  defp apply_section_border(cells, section_border, mode) do
    section_border = BorderDef.normalize(section_border)
    bounds = bounds(cells)

    Map.new(cells, fn {coords, %CellDef{} = cell_def} ->
      contribution =
        case mode do
          :all -> section_border
          :outline -> outline_contribution(section_border, coords, bounds)
        end

      {coords, %CellDef{cell_def | border: BorderDef.merge(cell_def.border, contribution)}}
    end)
  end

  defp bounds(cells) do
    xs = Enum.map(cells, fn {%SectionCoords{x: x}, _} -> x end)
    ys = Enum.map(cells, fn {%SectionCoords{y: y}, _} -> y end)
    {Enum.min(xs), Enum.max(xs), Enum.min(ys), Enum.max(ys)}
  end

  defp outline_contribution(
         %BorderDef{} = border,
         %SectionCoords{} = coords,
         {min_x, max_x, min_y, max_y}
       ) do
    %BorderDef{
      left: if(coords.x == min_x, do: border.left, else: nil),
      right: if(coords.x == max_x, do: border.right, else: nil),
      top: if(coords.y == min_y, do: border.top, else: nil),
      bottom: if(coords.y == max_y, do: border.bottom, else: nil)
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

  @doc """
  Find a point just below the area of the section.
  It should be used to ensure the sections are below each other.
  It allows opts:
    - move_x: integer(), default: 0
    - move_y: non_neg_integer(), default: 0

  TL - top left
  BR - bottom right
  TB - target below
  ----------------
  |A1|A2|A3|A4|A5|
  |B1|TL|B3|B4|B5|
  |C1|C2|C3|C4|C5|
  |D1|D2|D3|BR|D5|
  |E1|TB|E3|E4|E5|
  ----------------
  """
  @spec below(Section.t()) :: ExcelCoords.t()
  def below(%Section{} = section, opts \\ []) do
    move_x = Keyword.get(opts, :move_x, 0)
    move_y = Keyword.get(opts, :move_y, 0)

    ExcelCoords.new(
      section.top_left.x + move_x,
      section.bottom_right.y + move_y_just_below(section) + move_y
    )
  end

  @doc """
  Find a point just to the right to the area of the section.
  It should be used to ensure the sections are by each other.
  It allows opts:
    - move_x: non_neg_integer(), default: 0
    - move_y: integer(), default: 0

  TL - top left
  BR - bottom right
  TR - target right
  ----------------
  |A1|A2|A3|A4|A5|
  |B1|TL|B3|B4|TR|
  |C1|C2|C3|C4|C5|
  |D1|D2|D3|BR|D5|
  |E1|E2|E3|E4|E5|
  ----------------
  """
  @spec to_the_right(Section.t()) :: ExcelCoords.t()
  def to_the_right(%Section{} = section, opts \\ []) do
    move_x = Keyword.get(opts, :move_x, 0)
    move_y = Keyword.get(opts, :move_y, 0)

    ExcelCoords.new(
      section.bottom_right.x + move_x_just_right(section) + move_x,
      section.top_left.y + move_y
    )
  end

  @spec reduce_to_excel_cells([Section.t()]) :: CellDef.excel_cells()
  def reduce_to_excel_cells(sections) do
    sections
    |> Enum.uniq_by(& &1.name)
    |> Enum.map(&Section.to_excel_cells/1)
    |> Enum.reduce(%{}, fn excel_cells, acc ->
      Map.merge(acc, excel_cells)
    end)
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

  @doc """
  Identifies by how much you have to move the y value of the new Section's `top_left` point to just below another section.
  Simply: A scenario: you want to find the `top_left` point of section_2 based of the section_1 (which is a reference here).
  If section_1 is empty, then section_2 can start from the same `top_left`, so move by 0.
  Otherwise, we have to move by 1.
  """
  @spec move_y_just_below(Section.t()) :: 0 | 1
  def move_y_just_below(%Section{top_left: top_left, bottom_right: bottom_right} = _section)
      when top_left == bottom_right,
      do: 0

  def move_y_just_below(%Section{} = _section), do: 1

  @doc """
  Identifies by how much you have to move the x value of the new Section's `top_left` point to just right another section.
  Simply: A scenario: you want to find the `top_left` point of section_2 based of the section_1 (which is a reference here).
  If section_1 is empty, then section_2 can start from the same `top_left`, so move by 0.
  Otherwise, we have to move by 1.
  """
  @spec move_x_just_right(Section.t()) :: 0 | 1
  def move_x_just_right(%Section{top_left: top_left, bottom_right: bottom_right} = _section)
      when top_left == bottom_right,
      do: 0

  def move_x_just_right(%Section{} = _section), do: 1

  @spec pick_higher_int(non_neg_integer(), non_neg_integer()) :: non_neg_integer()
  defp pick_higher_int(int_1, int_2) when int_1 > int_2, do: int_1
  defp pick_higher_int(int_1, int_2) when int_1 <= int_2, do: int_2
end
