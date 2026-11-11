defmodule XLSXComposerTest do
  alias XLSXComposer.CellDef
  alias XLSXComposer.ExcelCoords
  alias XLSXComposer.Section
  alias XLSXComposer.SectionCoords
  alias XLSXComposer.Sheet

  use ExUnit.Case, async: true
  doctest XLSXComposer

  setup_all do
    section =
      Section.new(%{
        name: "s",
        top_left: ExcelCoords.new(1, 1),
        cells: %{SectionCoords.new(0, 0) => CellDef.new(%{content: "a"})}
      })

    %{
      sheet: Sheet.new(%{name: "One", sections: [section]}),
      other: Sheet.new(%{name: "Two", sections: [section]})
    }
  end

  describe "to_workbook/1" do
    test "wraps each sheet in order", %{sheet: sheet, other: other} do
      assert XLSXComposer.to_workbook([sheet, other]) ===
               %Elixlsx.Workbook{
                 sheets: [Sheet.to_elixlsx_sheet(sheet), Sheet.to_elixlsx_sheet(other)]
               }
    end
  end

  describe "write/2" do
    @tag :tmp_dir
    test "writes the file and returns Elixlsx's result", %{sheet: sheet, tmp_dir: tmp_dir} do
      path = Path.join(tmp_dir, "out.xlsx")
      assert {:ok, written} = XLSXComposer.write([sheet], path)
      assert to_string(written) == path
      assert File.regular?(path)
    end

    @tag :tmp_dir
    test "returns Elixlsx's error when the parent is a regular file", %{
      sheet: sheet,
      tmp_dir: tmp_dir
    } do
      parent = Path.join(tmp_dir, "file")
      File.write!(parent, "")
      assert {:error, {:EXIT, _}} = XLSXComposer.write([sheet], Path.join(parent, "out.xlsx"))
    end
  end

  defp guide_block(marker) do
    md = "../guides/example.md" |> Path.expand(__DIR__) |> File.read!()
    [_, code] = Regex.run(~r/<!-- #{marker} -->\s*```elixir\n(.*?)\n```/s, md)
    code
  end

  defp example_sheet do
    {sheet, _binding} = Code.eval_string(guide_block("example:build"))
    sheet
  end

  describe "guides/example.md" do
    test "build block produces the documented rows" do
      sheet = example_sheet()
      thin = [style: :thin]

      assert sheet.name == "Invoice"

      assert Sheet.to_elixlsx_rows(sheet) === [
               [],
               [
                 nil,
                 [
                   "Ship date",
                   bold: true,
                   color: "#FFFFFF",
                   bg_color: "#1F4E79",
                   border: [left: thin, right: thin, top: thin, bottom: thin]
                 ],
                 [
                   "Amount (USD)",
                   align_horizontal: :right,
                   bold: true,
                   color: "#FFFFFF",
                   bg_color: "#1F4E79",
                   border: [left: thin, right: thin, top: thin, bottom: thin]
                 ]
               ],
               [
                 nil,
                 [
                   {{2024, 7, 4}, {0, 0, 0}},
                   num_format: "mm/dd/yyyy",
                   border: [left: thin, top: thin, bottom: thin]
                 ],
                 [
                   1234.5678,
                   bg_color: "#FFF2CC",
                   num_format: "#,##0.00",
                   border: [right: thin, top: thin, bottom: [style: :double, color: "#CC3311"]]
                 ]
               ]
             ]
    end

    test "body section follows the header through Section.below/2" do
      code = guide_block("example:build")
      assert code =~ "top_left: ExcelCoords.new(2, 2)"

      {sheet, _binding} =
        code
        |> String.replace("top_left: ExcelCoords.new(2, 2)", "top_left: ExcelCoords.new(3, 4)")
        |> Code.eval_string()

      assert Map.has_key?(sheet.excel_cells, ExcelCoords.new(3, 5))
      assert Map.has_key?(sheet.excel_cells, ExcelCoords.new(4, 5))
      assert sheet.max_row_idx == 5
    end

    @tag :tmp_dir
    test "example writes a workbook with US formats", %{tmp_dir: tmp_dir} do
      assert guide_block("example:write") ==
               ~s|{:ok, _path} = XLSXComposer.write([sheet], "invoice.xlsx")|

      path = Path.join(tmp_dir, "invoice.xlsx")
      assert {:ok, _} = XLSXComposer.write([example_sheet()], path)
      assert File.regular?(path)

      {:ok, files} = :zip.unzip(String.to_charlist(path), [:memory])
      assert List.keymember?(files, ~c"xl/worksheets/sheet1.xml", 0)
      {_, styles} = List.keyfind(files, ~c"xl/styles.xml", 0)
      assert styles =~ ~s(formatCode="mm/dd/yyyy")
      assert styles =~ ~s(formatCode="#,##0.00")
      refute styles =~ "yyyy-mm-dd"
    end
  end
end
