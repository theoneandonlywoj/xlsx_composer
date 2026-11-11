defmodule XLSXComposer do
  @moduledoc """
  Declarative builder for `.xlsx` files on top of Elixlsx.

  Describe cells with `XLSXComposer.CellDef`, group them into relocatable
  `XLSXComposer.Section`s, collect sections into an `XLSXComposer.Sheet`, then
  call `write/2` (or `to_workbook/1` to keep tweaking the Elixlsx structs).
  """

  alias XLSXComposer.Sheet

  @doc """
  Converts sheets into an `Elixlsx.Workbook`, keeping their order.

  An empty list gives a workbook with no sheets; Elixlsx writes it, but Excel
  cannot open a workbook without sheets.

      iex> XLSXComposer.to_workbook([])
      %Elixlsx.Workbook{sheets: [], datetime: nil}
  """
  # Elixlsx.Workbook.t() types `sheets` as nonempty_list, but `[]` is allowed here.
  # credo:disable-for-next-line Credo.Check.Warning.SpecWithStruct
  @spec to_workbook(sheets :: [Sheet.t()]) :: %Elixlsx.Workbook{}
  def to_workbook(sheets) when is_list(sheets) do
    %Elixlsx.Workbook{sheets: Enum.map(sheets, &Sheet.to_elixlsx_sheet/1)}
  end

  @doc """
  Writes sheets to `path` and returns `Elixlsx.write_to/2`'s result unchanged.

  File-system failures come back as `{:error, reason}`. Invalid cells (styled
  cells without content, colors not in `"#RRGGBB"` form, unknown border styles)
  raise from Elixlsx while the workbook is compiled. Excel needs at least one
  sheet to open the file.
  """
  @spec write(sheets :: [Sheet.t()], path :: String.t()) :: {:ok, charlist()} | {:error, any()}
  def write(sheets, path) when is_list(sheets) do
    sheets
    |> to_workbook()
    |> Elixlsx.write_to(path)
  end
end
