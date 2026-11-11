defmodule XLSXComposer.SectionCoords do
  @moduledoc """
  Location of a cell in a section: 0-based `x` (column) and `y` (row) offsets
  from the section's `top_left`.

  This allows us to move a group of cells at once.
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
