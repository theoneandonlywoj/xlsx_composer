defmodule XLSXComposer.Section do
  @moduledoc """
  A named group of cells keyed by `XLSXComposer.SectionCoords` and placed at a
  `top_left` `XLSXComposer.ExcelCoords`, so it can be moved, reasoned about and
  tested as one unit.

  Nothing checks overlap automatically: when sections overlap, the later one
  wins silently. `overlap?/2` only tests whether either section's top-left corner
  falls inside the other (it misses e.g. cross-shaped overlaps), so it is not a
  full overlap check. Sections with a duplicate name are dropped when sheets are
  built (first wins).

  `section_border` adds outward-facing cardinal sides in the default `:outline`
  mode, or every supplied side in `:all` mode. Existing cell sides take precedence.
  Any other `section_border_mode` (including an explicit `nil`) sets the mode to
  `nil` and drops the section border entirely.
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
          section_border_mode: :outline | :all | nil
        }

  @type new_attrs() :: %{
          optional(:section_border) => BorderDef.t() | keyword() | nil,
          optional(:section_border_mode) => :outline | :all | nil,
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
    section_border_mode = normalize_border_mode(Map.get(args, :section_border_mode, :outline))
    section_border = if section_border_mode, do: args[:section_border], else: nil

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

  defp normalize_border_mode(mode) when mode in [:outline, :all], do: mode
  defp normalize_border_mode(_mode), do: nil

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
  @spec below(Section.t(), keyword()) :: ExcelCoords.t()
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
  @spec to_the_right(Section.t(), keyword()) :: ExcelCoords.t()
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
  How far the next section's `top_left` y must move to sit just below this one:
  0 when the section has no cells (it takes no space), otherwise 1. A one-cell
  section is not empty, although its `top_left` and `bottom_right` are equal.
  """
  @spec move_y_just_below(Section.t()) :: 0 | 1
  def move_y_just_below(%Section{cells: cells}) when map_size(cells) == 0, do: 0
  def move_y_just_below(%Section{}), do: 1

  @doc """
  How far the next section's `top_left` x must move to sit just right of this one:
  0 when the section has no cells, otherwise 1 (see `move_y_just_below/1`).
  """
  @spec move_x_just_right(Section.t()) :: 0 | 1
  def move_x_just_right(%Section{cells: cells}) when map_size(cells) == 0, do: 0
  def move_x_just_right(%Section{}), do: 1

  @spec pick_higher_int(non_neg_integer(), non_neg_integer()) :: non_neg_integer()
  defp pick_higher_int(int_1, int_2) when int_1 > int_2, do: int_1
  defp pick_higher_int(int_1, int_2) when int_1 <= int_2, do: int_2
end
