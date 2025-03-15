defmodule XLSXComposer.ExcelCoords do
  @moduledoc """
  #{__MODULE__} represent excel coords where the x denotes the column (represented as integer, A = 1) and y denotes the row.

  Both values start from 1 (to mimic the Excel notation and interchangeability)!
  """

  alias XLSXComposer.ExcelCoords
  alias XLSXComposer.SectionCoords

  @type t() :: %ExcelCoords{
          x: x(),
          y: y(),
          pretty: String.t()
        }

  @type x() :: pos_integer()
  @type y() :: pos_integer()

  @type area_t() :: {t(), t()}

  defstruct x: 1,
            y: 1,
            pretty: "A1"

  @spec new({x(), y()}) :: t()
  def new({x, y}), do: new(x, y)

  @spec new(x(), y()) :: t()
  def new(x \\ 1, y \\ 1) do
    %ExcelCoords{
      x: x,
      y: y,
      pretty: to_pretty(x, y)
    }
  end

  @spec displace(ExcelCoords.t(), SectionCoords.t()) :: ExcelCoords.t()
  def displace(%ExcelCoords{} = excel_coords, %SectionCoords{} = section_cords) do
    ExcelCoords.new(excel_coords.x + section_cords.x, excel_coords.y + section_cords.y)
  end

  @spec column(ExcelCoords.t()) :: pos_integer()
  def column(%ExcelCoords{} = excel_coords),
    do: excel_coords.x

  @spec to_pretty(ExcelCoords.t()) :: String.t()
  def to_pretty(%ExcelCoords{} = excel_coords),
    do: to_pretty(excel_coords.x, excel_coords.y)

  @spec to_pretty(integer(), integer()) :: String.t()
  def to_pretty(x, y),
    do: "#{Elixlsx.Util.encode_col(x)}#{y}"
end
