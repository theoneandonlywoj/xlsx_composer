defmodule XLSXComposer.SectionCoords do
  @moduledoc """
  #{__MODULE__} represents location of the cell in a given section.

  This approach allows use to move a group of cells at ones.
  Furthermore, this approach allows for an easier understanding of the structure of the document while being performant.
  """
  alias XLSXComposer.SectionCoords

  @type t() :: %SectionCoords{
          x: x(),
          y: y()
        }

  @type x() :: non_neg_integer()
  @type y() :: non_neg_integer()

  defstruct x: 0,
            y: 0

  @spec new({x(), y()}) :: t()
  def new({x, y}), do: new(x, y)

  @spec new(x(), y()) :: t()
  def new(x \\ 0, y \\ 0) do
    %SectionCoords{
      x: x,
      y: y
    }
  end
end
