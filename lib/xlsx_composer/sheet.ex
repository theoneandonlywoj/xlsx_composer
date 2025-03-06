defmodule XLSXComposer.Sheet do
  @moduledoc """
  #{__MODULE__} corresponds to Elixls's Sheet and translates into that if you want to do additional stuff or if you have to work around limitations of this library.
  """

  alias XLSXComposer.CellDef
  alias XLSXComposer.ExcelCoords
  alias XLSXComposer.Section
  alias XLSXComposer.Sheet

  @type t() :: %Sheet{
          name: String.t(),
          excel_cells: CellDef.excel_cells(),
          max_row_idx: integer()
        }

  @type excel_cell_by_row_idx() :: %{
          integer() => [CellDef.excel_cells()]
        }

  defstruct name: "",
            excel_cells: %{},
            max_row_idx: 0

  @spec build(map()) :: {:ok, Sheet.t()} | {:error, term()}
  def build(args) do
    sections = args[:sections] || []

    max_row_idx =
      sections
      |> Enum.map(& &1.bottom_right.y)
      |> Enum.max()

    excel_cells =
      sections
      |> Enum.uniq_by(& &1.name)
      |> Enum.map(&Section.to_excel_cells/1)
      |> Enum.reduce(%{}, fn excel_cells, acc ->
        Map.merge(acc, excel_cells)
      end)

    %Sheet{
      name: args[:name] || "",
      excel_cells: excel_cells,
      max_row_idx: max_row_idx
    }
    |> validate()
  end

  @spec validate(Sheet.t()) :: {:ok, Sheet.t()} | {:error, term()}
  def validate(%Sheet{} = sheet) do
    {:ok, sheet}
  end

  @spec to_elixlsx_rows(Sheet.t()) :: []
  def to_elixlsx_rows(%Sheet{} = sheet) do
    group_excel_cell_by_row_idx =
      group_excel_cell_by_row_idx(sheet.excel_cells)

    excel_rows_max_column =
      excel_rows_max_column(group_excel_cell_by_row_idx)

    1..sheet.max_row_idx
    |> Enum.map(fn
      row_idx ->
        empty_row =
          excel_rows_max_column
          |> Map.get(row_idx, 0)
          |> Sheet.generate_empty_row()

        group_excel_cell_by_row_idx
        |> Map.get(row_idx, [])
        |> Enum.reduce(empty_row, fn excel_coords, acc ->
          elixlsx_cell_def =
            sheet.excel_cells
            |> Map.get(excel_coords)
            |> CellDef.to_elixlsx_cell_def()

          # x - 1 because Excel cords start from 0
          list_idx = excel_coords.x - 1
          List.replace_at(acc, list_idx, elixlsx_cell_def)
        end)
    end)
  end

  # @spec to_elixlsx_sheet(Sheet.t()) :: Elixlsx.Sheet.t()
  def to_elixlsx_sheet(%Sheet{} = sheet) do
    %Elixlsx.Sheet{
      name: sheet.name,
      rows: to_elixlsx_rows(sheet)
    }
  end

  @spec excel_rows_max_column(excel_cell_by_row_idx()) :: %{integer() => integer()}
  def excel_rows_max_column(grouped_excel_cell_by_row_idx) do
    grouped_excel_cell_by_row_idx
    |> Enum.map(fn {row, excel_coords} ->
      # Max Column for given row
      max_column =
        excel_coords
        |> Enum.map(&ExcelCoords.column/1)
        |> Enum.max()

      {row, max_column}
    end)
    |> Map.new()
  end

  @spec generate_empty_row(non_neg_integer()) :: [nil]
  def generate_empty_row(0), do: []
  def generate_empty_row(max_column), do: Enum.map(1..max_column, fn _ -> nil end)

  @spec group_excel_cell_by_row_idx(CellDef.excel_cells()) :: excel_cell_by_row_idx()
  def group_excel_cell_by_row_idx(excel_cells) do
    excel_cells
    |> Map.keys()
    |> Enum.group_by(& &1.y)
  end

  defmodule Error do
    @moduledoc """
    #{__MODULE__} represents errors (not yet implemented).
    """
    @type t() :: %Error{
            msg: String.t(),
            severity: :error | :warning
          }
    defstruct msg: "",
              severity: :error

    @spec report_overlap(Section.t(), Section.t()) :: Error.t()
    def report_overlap(%Section{} = section_1, %Section{} = section_2) do
      %Error{
        msg: "sections with following names overlap: [#{section_1.name}, #{section_2.name}]",
        severity: :error
      }
    end
  end
end
