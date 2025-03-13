defmodule XLSXComposer.ExcelCoordsTest do
  alias XLSXComposer.ExcelCoords
  alias XLSXComposer.SectionCoords

  use ExUnit.Case

  doctest XLSXComposer.ExcelCoords

  describe "new/1" do
    test "news for A1" do
      assert ExcelCoords.new({1, 1}) ===
               %ExcelCoords{x: 1, y: 1, pretty: "A1"}
    end

    test "news for Z1" do
      assert ExcelCoords.new({26, 1}) ===
               %ExcelCoords{x: 26, y: 1, pretty: "Z1"}
    end

    test "news for A10000000 (Google Sheet row limit)" do
      assert ExcelCoords.new({1, 10_000_000}) ===
               %ExcelCoords{
                 x: 1,
                 y: 10_000_000,
                 pretty: "A10000000"
               }
    end

    test "news for AA1 (beyond just A-Z)" do
      assert ExcelCoords.new({27, 1}) ===
               %ExcelCoords{x: 27, y: 1, pretty: "AA1"}
    end

    test "news for ZZZ1 (Google Sheet column limit)" do
      assert ExcelCoords.new({18_278, 1}) ===
               %ExcelCoords{x: 18_278, y: 1, pretty: "ZZZ1"}
    end
  end

  describe "new/2" do
    test "news for A1" do
      assert ExcelCoords.new(1, 1) ===
               %ExcelCoords{x: 1, y: 1, pretty: "A1"}
    end

    test "news for Z1" do
      assert ExcelCoords.new(26, 1) ===
               %ExcelCoords{x: 26, y: 1, pretty: "Z1"}
    end

    test "news for A10000000 (Google Sheet row limit)" do
      assert ExcelCoords.new(1, 10_000_000) ===
               %ExcelCoords{
                 x: 1,
                 y: 10_000_000,
                 pretty: "A10000000"
               }
    end

    test "news for AA1 (beyond just A-Z)" do
      assert ExcelCoords.new(27, 1) ===
               %ExcelCoords{x: 27, y: 1, pretty: "AA1"}
    end

    test "news for ZZZ1 (Google Sheet column limit)" do
      assert ExcelCoords.new(18_278, 1) ===
               %ExcelCoords{x: 18_278, y: 1, pretty: "ZZZ1"}
    end
  end

  describe "displace/2" do
    setup do
      excel_coords = %ExcelCoords{x: 5, y: 5, pretty: "E5"}

      {:ok, %{excel_coords: excel_coords}}
    end

    test "displace by (0, 0)", %{excel_coords: excel_coords} do
      assert ExcelCoords.displace(
               excel_coords,
               SectionCoords.new(0, 0)
             ) === excel_coords
    end

    test "displace by (1, 1)", %{excel_coords: excel_coords} do
      assert ExcelCoords.displace(
               excel_coords,
               SectionCoords.new(1, 1)
             ) === %ExcelCoords{
               x: 6,
               y: 6,
               pretty: "F6"
             }
    end

    test "displace by (1, -1)", %{excel_coords: excel_coords} do
      assert ExcelCoords.displace(
               excel_coords,
               SectionCoords.new(1, -1)
             ) === %ExcelCoords{
               x: 6,
               y: 4,
               pretty: "F4"
             }
    end

    test "displace by (-1, -1)", %{excel_coords: excel_coords} do
      assert ExcelCoords.displace(
               excel_coords,
               SectionCoords.new(-1, -1)
             ) === %ExcelCoords{
               x: 4,
               y: 4,
               pretty: "D4"
             }
    end

    test "displace by (-1, 1)", %{excel_coords: excel_coords} do
      assert ExcelCoords.displace(
               excel_coords,
               SectionCoords.new(-1, 1)
             ) === %ExcelCoords{
               x: 4,
               y: 6,
               pretty: "D6"
             }
    end
  end
end
