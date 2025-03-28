defmodule XLSXComposer.CellDef do
  @moduledoc """
  #{__MODULE__} showcases all supported options as a struct that is later folded into representation required by Elixlsx.

  `:configuration` is a map of settings you might want to use to tag elements and later on, globally collect and apply an additional style if required.
  """
  alias XLSXComposer.CellDef
  alias XLSXComposer.ExcelCoords
  alias XLSXComposer.SectionCoords

  @type t() :: %CellDef{
          # Content / Text
          content: content(),
          wrap_text: boolean() | nil,
          font: String | nil,
          # Align
          align_vertical: align_vertical() | nil,
          align_horizontal: align_horizontal() | nil,
          # Style
          bold: boolean() | nil,
          italic: boolean() | nil,
          underline: boolean() | nil,
          strike: boolean() | nil,
          size: pos_integer() | nil,
          # Colors
          color: String.t() | nil,
          bg_color: String.t() | nil,
          # Numerical Format
          num_format: String.t() | nil,
          # Date
          datetime: boolean() | nil,
          yyyymmdd: String.t() | nil,
          # Border
          border: Keyword.t() | nil,
          # Configuration
          configuration: %{String.t() => any()}
        }

  @type new_attrs() :: %{
          optional(:content) => content(),
          optional(:wrap_text) => boolean(),
          optional(:font) => String.t(),
          optional(:align_vertical) => align_vertical(),
          optional(:align_horizontal) => align_horizontal(),
          optional(:bold) => boolean(),
          optional(:italic) => boolean(),
          optional(:underline) => boolean(),
          optional(:strike) => boolean(),
          optional(:size) => pos_integer(),
          optional(:color) => String.t(),
          optional(:bg_color) => String.t(),
          optional(:num_format) => String.t(),
          optional(:datetime) => boolean(),
          optional(:yyyymmdd) => String.t(),
          optional(:border) => Keyword.t(),
          optional(:configuration) => %{String.t() => any()}
        }

  @type style_option() ::
          {:wrap_text, boolean()}
          | {:font, String.t()}
          | {:align_vertical, align_horizontal()}
          | {:align_horizontal, align_vertical()}
          | {:bold, boolean()}
          | {:italic, boolean()}
          | {:underline, boolean()}
          | {:strike, boolean()}
          | {:size, pos_integer()}
          | {:color, String.t()}
          | {:bg_color, String.t()}
          | {:num_format, String.t()}
          | {:datetime, boolean()}
          | {:yyyymmdd, boolean()}

  @type align_horizontal() :: :left | :right | :center | :justify | :general | :fill

  @type align_vertical() :: :top | :bottom | :center

  @type border_style() :: list()

  @type content() :: any()

  @type elixlsx_definition() :: [content() | {style_option(), any()}]

  @type section_cells() :: %{SectionCoords.t() => CellDef.t()}

  @type excel_cells() :: %{ExcelCoords.t() => CellDef.t()}

  @options [
    :wrap_text,
    :font,
    :align_vertical,
    :align_horizontal,
    :bold,
    :italic,
    :underline,
    :strike,
    :size,
    :color,
    :bg_color,
    :num_format,
    :datetime,
    :yyyymmdd
  ]

  defstruct content: nil,
            wrap_text: nil,
            font: nil,
            # Align
            align_vertical: nil,
            align_horizontal: nil,
            # Style
            bold: nil,
            italic: nil,
            underline: nil,
            strike: nil,
            size: nil,
            # Colors
            color: nil,
            bg_color: nil,
            # Numerical Format
            num_format: nil,
            # Date
            datetime: nil,
            yyyymmdd: nil,
            # Border
            border: nil,
            # Configuration
            configuration: %{}

  @spec new(new_attrs()) :: t()
  def new(args \\ %{}) do
    %CellDef{
      # Content / Text
      content: args[:content] || nil,
      wrap_text: args[:wrap_text],
      font: args[:font],
      # Align
      align_vertical: args[:align_vertical],
      align_horizontal: args[:align_horizontal],
      # Style
      bold: args[:bold],
      italic: args[:italic],
      underline: args[:underline],
      strike: args[:strike],
      size: args[:size],
      # Colors
      color: args[:color],
      bg_color: args[:bg_color],
      # Numerical Format
      num_format: args[:num_format],
      # Date
      datetime: args[:datetime],
      yyyymmdd: args[:yyyymmdd],
      # Border
      border: args[:border],
      # Configuration
      configuration: args[:configuration] || %{}
    }
  end

  @spec set_content(CellDef.t(), content()) :: CellDef.t()
  def set_content(%CellDef{} = cell_def, content), do: %CellDef{cell_def | content: content}

  @spec set_style_option(CellDef.t(), style_option()) :: CellDef.t()
  def set_style_option(%CellDef{} = cell_def, {option, value}) do
    Map.put(cell_def, option, value)
  end

  @spec set_configuration(CellDef.t(), atom(), any()) :: CellDef.t()
  def set_configuration(%CellDef{configuration: conf} = cell_def, key, value) do
    Map.put(cell_def, :configuration, Map.put(conf, key, value))
  end

  @spec match_configuration?(CellDef.t(), atom(), fun()) :: CellDef.t()
  def match_configuration?(%CellDef{configuration: conf} = _cell_def, key, func) do
    conf
    |> Map.get(key)
    |> func.()
  end

  @spec displace(ExcelCoords.t(), SectionCoords.t()) :: ExcelCoords.t()
  def displace(%ExcelCoords{} = excel_coords, %SectionCoords{} = section_cords) do
    ExcelCoords.new(excel_coords.x + section_cords.x, excel_coords.y + section_cords.y)
  end

  @spec to_elixlsx_cell_def(CellDef.t() | nil) :: elixlsx_definition() | nil
  def to_elixlsx_cell_def(nil), do: nil

  def to_elixlsx_cell_def(%CellDef{} = cell_def) do
    []
    |> maybe_set_content(cell_def.content)
    |> then(
      &Enum.reduce(@options, &1, fn style_option, acc ->
        set_on_not_nil(acc, Map.get(cell_def, style_option), style_option)
      end)
    )
    |> maybe_set_border(cell_def.border)
  end

  @spec maybe_set_content(elixlsx_definition(), nil | any()) :: elixlsx_definition()
  defp maybe_set_content(definition, nil), do: definition
  defp maybe_set_content(definition, content), do: [content] ++ definition

  @spec maybe_set_border(elixlsx_definition(), nil | border_style()) :: elixlsx_definition()
  defp maybe_set_border(definition, border_list) when is_list(border_list),
    do: definition ++ [{:border, border_list}]

  defp maybe_set_border(definition, _), do: definition

  @spec set_on_not_nil(elixlsx_definition(), nil | any(), atom()) :: elixlsx_definition()
  defp set_on_not_nil(definition, nil, _), do: definition
  defp set_on_not_nil(definition, value, value_atom), do: definition ++ [{value_atom, value}]
end
