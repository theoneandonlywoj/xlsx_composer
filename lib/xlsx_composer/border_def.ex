defmodule XLSXComposer.BorderDef do
  @moduledoc """
  A typed border definition converted to the keyword form expected by Elixlsx.

  Presets and `all:` fill the four cardinal sides. Explicit sides take precedence
  over `all:`, which takes precedence over the preset. Diagonals are explicit.
  """

  defmodule Side do
    @moduledoc "Describes the style and color of one border side."

    defstruct style: nil, color: nil

    @type t() :: %__MODULE__{style: atom() | nil, color: String.t() | nil}
    @type new_attrs() :: %{optional(:style) => atom(), optional(:color) => String.t()}

    @doc "Creates a side, leaving unspecified properties unset."
    @spec new(args :: new_attrs()) :: t()
    def new(args \\ %{}) do
      %__MODULE__{style: args[:style], color: args[:color]}
    end
  end

  alias XLSXComposer.BorderDef
  alias XLSXComposer.BorderDef.Side

  defstruct left: nil,
            right: nil,
            top: nil,
            bottom: nil,
            diagonal: nil,
            diagonal_up: nil,
            diagonal_down: nil,
            preset: nil

  @type t() :: %BorderDef{
          left: Side.t() | nil,
          right: Side.t() | nil,
          top: Side.t() | nil,
          bottom: Side.t() | nil,
          diagonal: Side.t() | nil,
          diagonal_up: boolean() | nil,
          diagonal_down: boolean() | nil,
          preset: atom() | nil
        }

  @type new_attrs() :: %{
          optional(:left) => Side.t(),
          optional(:right) => Side.t(),
          optional(:top) => Side.t(),
          optional(:bottom) => Side.t(),
          optional(:diagonal) => Side.t(),
          optional(:all) => Side.t(),
          optional(:preset) => atom(),
          optional(:diagonal_up) => boolean(),
          optional(:diagonal_down) => boolean()
        }

  @doc "Creates a border, expanding `all:` and the preset into cardinal sides."
  @spec new(args :: new_attrs()) :: t()
  def new(args \\ %{}) do
    all_side = args[:all] || preset_side(args[:preset])

    %BorderDef{
      left: args[:left] || all_side,
      right: args[:right] || all_side,
      top: args[:top] || all_side,
      bottom: args[:bottom] || all_side,
      diagonal: args[:diagonal],
      diagonal_up: args[:diagonal_up],
      diagonal_down: args[:diagonal_down],
      preset: args[:preset]
    }
  end

  @doc "Converts a border to ordered Elixlsx keywords, omitting empty sides and false flags."
  @spec to_elixlsx(border_def :: t() | nil) :: keyword()
  def to_elixlsx(nil), do: []

  def to_elixlsx(%BorderDef{} = border_def) do
    border_def = normalize(border_def)

    []
    |> add_side(:left, border_def.left)
    |> add_side(:right, border_def.right)
    |> add_side(:top, border_def.top)
    |> add_side(:bottom, border_def.bottom)
    |> add_side(:diagonal, border_def.diagonal)
    |> add_flag(:diagonal_up, border_def.diagonal_up)
    |> add_flag(:diagonal_down, border_def.diagonal_down)
  end

  @doc "Normalizes a typed or raw border, expanding and clearing any preset."
  @spec normalize(border_def :: t() | keyword() | nil) :: t() | nil
  def normalize(nil), do: nil

  def normalize(%BorderDef{} = border_def) do
    side = preset_side(border_def.preset)

    %BorderDef{
      border_def
      | left: border_def.left || side,
        right: border_def.right || side,
        top: border_def.top || side,
        bottom: border_def.bottom || side,
        preset: nil
    }
  end

  def normalize(keyword) when is_list(keyword), do: from_keyword(keyword)

  @doc "Converts raw Elixlsx border keywords into a typed border."
  @spec from_keyword(keyword :: keyword() | nil) :: t() | nil
  def from_keyword(nil), do: nil

  def from_keyword(keyword) when is_list(keyword) do
    %BorderDef{
      left: keyword[:left] |> side_from_props(),
      right: keyword[:right] |> side_from_props(),
      top: keyword[:top] |> side_from_props(),
      bottom: keyword[:bottom] |> side_from_props(),
      diagonal: keyword[:diagonal] |> side_from_props(),
      diagonal_up: keyword[:diagonal_up],
      diagonal_down: keyword[:diagonal_down]
    }
  end

  @doc "Merges borders with first-side precedence and OR semantics for diagonal flags."
  @spec merge(first :: t() | keyword() | nil, second :: t() | keyword() | nil) :: t() | nil
  def merge(nil, nil), do: nil
  def merge(nil, other), do: normalize(other)
  def merge(other, nil), do: normalize(other)

  def merge(first, second) do
    first = normalize(first)
    second = normalize(second)

    %BorderDef{
      left: first.left || second.left,
      right: first.right || second.right,
      top: first.top || second.top,
      bottom: first.bottom || second.bottom,
      diagonal: first.diagonal || second.diagonal,
      diagonal_up: first.diagonal_up || second.diagonal_up,
      diagonal_down: first.diagonal_down || second.diagonal_down
    }
  end

  defp preset_side(nil), do: nil
  defp preset_side(style), do: %Side{style: style}

  defp side_from_props(nil), do: nil

  defp side_from_props(props) when is_list(props) do
    %Side{style: props[:style], color: props[:color]}
  end

  defp add_side(keyword, _side, nil), do: keyword
  defp add_side(keyword, _side, %Side{style: nil, color: nil}), do: keyword

  defp add_side(keyword, side, %Side{} = side_def) do
    props =
      []
      |> add_if(side_def.style, :style)
      |> add_if(side_def.color, :color)

    keyword ++ [{side, props}]
  end

  defp add_flag(keyword, _flag, nil), do: keyword
  defp add_flag(keyword, _flag, false), do: keyword
  defp add_flag(keyword, flag, true), do: keyword ++ [{flag, true}]

  defp add_if(list, nil, _key), do: list
  defp add_if(list, value, key), do: list ++ [{key, value}]
end
