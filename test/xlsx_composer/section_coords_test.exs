defmodule XLSXComposer.SectionCoordsTest do
  alias XLSXComposer.SectionCoords

  use ExUnit.Case

  doctest XLSXComposer.SectionCoords

  describe "new/1" do
    test "news for (0, 0)" do
      assert SectionCoords.new({0, 0}) ===
               %SectionCoords{x: 0, y: 0}
    end

    test "news for (1, 1)" do
      assert SectionCoords.new({1, 1}) ===
               %SectionCoords{x: 1, y: 1}
    end

    test "news for (1, -1)" do
      assert SectionCoords.new({1, -1}) ===
               %SectionCoords{x: 1, y: -1}
    end

    test "news for (-1, -1)" do
      assert SectionCoords.new({-1, -1}) ===
               %SectionCoords{x: -1, y: -1}
    end

    test "news for (-1, 1)" do
      assert SectionCoords.new({-1, 1}) ===
               %SectionCoords{x: -1, y: 1}
    end
  end

  describe "new/2" do
    test "news for (0, 0)" do
      assert SectionCoords.new(0, 0) ===
               %SectionCoords{x: 0, y: 0}
    end

    test "news for (1, 1)" do
      assert SectionCoords.new(1, 1) ===
               %SectionCoords{x: 1, y: 1}
    end

    test "news for (1, -1)" do
      assert SectionCoords.new(1, -1) ===
               %SectionCoords{x: 1, y: -1}
    end

    test "news for (-1, -1)" do
      assert SectionCoords.new(-1, -1) ===
               %SectionCoords{x: -1, y: -1}
    end

    test "news for (-1, 1)" do
      assert SectionCoords.new(-1, 1) ===
               %SectionCoords{x: -1, y: 1}
    end
  end
end
