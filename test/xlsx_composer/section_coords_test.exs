defmodule XLSXComposer.SectionCoordsTest do
  alias XLSXComposer.SectionCoords

  use ExUnit.Case

  doctest XLSXComposer.SectionCoords

  describe "build/1" do
    test "builds for (0, 0)" do
      assert SectionCoords.build({0, 0}) ===
               %SectionCoords{x: 0, y: 0}
    end

    test "builds for (1, 1)" do
      assert SectionCoords.build({1, 1}) ===
               %SectionCoords{x: 1, y: 1}
    end

    test "builds for (1, -1)" do
      assert SectionCoords.build({1, -1}) ===
               %SectionCoords{x: 1, y: -1}
    end

    test "builds for (-1, -1)" do
      assert SectionCoords.build({-1, -1}) ===
               %SectionCoords{x: -1, y: -1}
    end

    test "builds for (-1, 1)" do
      assert SectionCoords.build({-1, 1}) ===
               %SectionCoords{x: -1, y: 1}
    end
  end

  describe "build/2" do
    test "builds for (0, 0)" do
      assert SectionCoords.build(0, 0) ===
               %SectionCoords{x: 0, y: 0}
    end

    test "builds for (1, 1)" do
      assert SectionCoords.build(1, 1) ===
               %SectionCoords{x: 1, y: 1}
    end

    test "builds for (1, -1)" do
      assert SectionCoords.build(1, -1) ===
               %SectionCoords{x: 1, y: -1}
    end

    test "builds for (-1, -1)" do
      assert SectionCoords.build(-1, -1) ===
               %SectionCoords{x: -1, y: -1}
    end

    test "builds for (-1, 1)" do
      assert SectionCoords.build(-1, 1) ===
               %SectionCoords{x: -1, y: 1}
    end
  end
end
