defmodule XLSXComposer do
  @moduledoc """
  Documentation for `XLSXComposer`.
  """

  @doc """
  Example 1.

  ## Examples

    iex> alias XLSXComposer.{CellDef, ExcelCoords, Section, SectionCoords}
    iex> _section_1 =
    iex>   Section.build(%{
    iex>     name: "section_1",
    iex>     top_left: ExcelCoords.build({2, 2}),
    iex>     cells: %{
    iex>       SectionCoords.build(0, 0) =>
    iex>         CellDef.build(%{
    iex>           content: "Name",
    iex>           bold: true
    iex>         }),
    iex>       SectionCoords.build(2, 0) =>
    iex>         CellDef.build(%{
    iex>           content: "Summary Required?",
    iex>           bold: true
    iex>         }),
    iex>       SectionCoords.build(4, 0) =>
    iex>         CellDef.build(%{
    iex>           content: "Calls",
    iex>           bold: true
    iex>         }),
    iex>       SectionCoords.build(5, 0) =>
    iex>         CellDef.build(%{
    iex>           content: "Sales",
    iex>           bold: true
    iex>         })
    iex>     }
    iex>   })
    iex> _section_2 =
    iex>   Section.build(%{
    iex>     name: "section_2",
    iex>     top_left: ExcelCoords.build({2, 4}),
    iex>     cells: %{
    iex>       # Row 0
    iex>       SectionCoords.build(0, 0) => CellDef.build(%{
    iex>         content: 1.1111,
    iex>         num_format: "0.00"
    iex>       }),
    iex>       SectionCoords.build(1, 0) => CellDef.build(%{
    iex>         content: 1.1111,
    iex>         num_format: "0.00"
    iex>       }),
    iex>       SectionCoords.build(4, 0) =>
    iex>       CellDef.build(%{
    iex>         content: "Summary Required?",
    iex>         bold: true
    iex>       }),
    iex>       # Row 1
    iex>       SectionCoords.build(2, 1) =>
    iex>       CellDef.build(%{
    iex>         content: "Something Else",
    iex>         bold: false
    iex>       }),
    iex>       # Row 2
    iex>       SectionCoords.build(0, 2) =>
    iex>       CellDef.build(%{
    iex>         content: 2.3,
    iex>         num_format: "0.0000"
    iex>       }),
    iex>       SectionCoords.build(1, 2) =>       CellDef.build(%{
    iex>         content: 2.99,
    iex>         num_format: "0.0000"
    iex>       }),
    iex>       SectionCoords.build(5, 2) => CellDef.build(%{
    iex>         content: "Summary Required?",
    iex>         bold: true
    iex>       }),
    iex>       # Row 3
    iex>       SectionCoords.build(2, 3) => CellDef.build(%{
    iex>         content: "Something Else",
    iex>         bold: false
    iex>       }),
    iex>       SectionCoords.build(4, 3) =>
    iex>       CellDef.build(%{
    iex>         content: "I don't know what to put here",
    iex>         bold: false
    iex>       }),
    iex>       # Row 4
    iex>       SectionCoords.build(0, 4) =>
    iex>       CellDef.build(%{
    iex>         content: -1.1111,
    iex>         num_format: "0.0"
    iex>       }),
    iex>       SectionCoords.build(1, 4) => CellDef.build(%{
    iex>         content: -1.1111,
    iex>         num_format: "0.000"
    iex>       }),
    iex>     }
    iex>   })

  """
  @spec example() :: :ok
  def example() do
    :ok
  end
end
