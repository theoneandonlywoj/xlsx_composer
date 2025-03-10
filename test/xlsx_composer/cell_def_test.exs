defmodule XLSXComposer.CellDefTest do
  alias XLSXComposer.CellDef

  use ExUnit.Case, async: true

  doctest XLSXComposer.CellDef

  describe "build/1" do
    # Content
    test "builds for no provided content and sets :content" do
      content = nil
      assert CellDef.build(%{content: content}) === %CellDef{content: content}
    end

    test "builds for provided content and sets :content" do
      content = "content"
      assert CellDef.build(%{content: content}) === %CellDef{content: content}
    end

    # Wrap text
    test "builds for provided wrap_text and sets :wrap_text" do
      value = true
      key = :wrap_text

      assert Map.new()
             |> Map.put(key, value)
             |> CellDef.build() === %CellDef{wrap_text: value}
    end

    # Font
    test "builds for provided font and sets :font" do
      value = "Courier New"
      key = :font

      assert Map.new()
             |> Map.put(key, value)
             |> CellDef.build() === %CellDef{font: value}
    end

    # Align Vertical
    test "builds for provided align_vertical and sets :align_vertical" do
      value = true
      key = :align_vertical

      assert Map.new()
             |> Map.put(key, value)
             |> CellDef.build() === %CellDef{align_vertical: value}
    end

    # Align Horizontal
    test "builds for provided align_horizontal and sets :align_horizontal" do
      value = true
      key = :align_horizontal

      assert Map.new()
             |> Map.put(key, value)
             |> CellDef.build() === %CellDef{align_horizontal: value}
    end

    # Bold
    test "builds for provided bold and sets :bold" do
      value = true
      key = :bold

      assert Map.new()
             |> Map.put(key, value)
             |> CellDef.build() === %CellDef{bold: value}
    end

    # Italic
    test "builds for provided italic and sets :italic" do
      value = true
      key = :italic

      assert Map.new()
             |> Map.put(key, value)
             |> CellDef.build() === %CellDef{italic: value}
    end

    # Underline
    test "builds for provided underline and sets :underline" do
      value = true
      key = :underline

      assert Map.new()
             |> Map.put(key, value)
             |> CellDef.build() === %CellDef{underline: value}
    end

    # Strike
    test "builds for provided strike and sets :strike" do
      value = true
      key = :strike

      assert Map.new()
             |> Map.put(key, value)
             |> CellDef.build() === %CellDef{strike: value}
    end

    # Size
    test "builds for provided size and sets :size" do
      value = 20
      key = :size

      assert Map.new()
             |> Map.put(key, value)
             |> CellDef.build() === %CellDef{size: value}
    end

    # Color
    test "builds for provided color and sets :color" do
      value = "#ffff00"
      key = :color

      assert Map.new()
             |> Map.put(key, value)
             |> CellDef.build() === %CellDef{color: value}
    end

    # Background Color
    test "builds for provided bg_color and sets :bg_color" do
      value = "#ffff00"
      key = :bg_color

      assert Map.new()
             |> Map.put(key, value)
             |> CellDef.build() === %CellDef{bg_color: value}
    end

    # Number Format
    test "builds for provided num_formta and sets :num_format" do
      value = "0.00"
      key = :num_format

      assert Map.new()
             |> Map.put(key, value)
             |> CellDef.build() === %CellDef{num_format: value}
    end

    # DateTime Format
    test "builds for provided datetime and sets :datetime" do
      value = true
      key = :datetime

      assert Map.new()
             |> Map.put(key, value)
             |> CellDef.build() === %CellDef{datetime: value}
    end

    # YYYYMMDD Format
    test "builds for provided yyyymmdd and sets :yyyymmdd" do
      value = true
      key = :yyyymmdd

      assert Map.new()
             |> Map.put(key, value)
             |> CellDef.build() === %CellDef{yyyymmdd: value}
    end

    # Border
    test "builds for provided border and sets :border" do
      value = [bottom: [style: :double, color: "#cc3311"]]
      key = :border

      assert Map.new()
             |> Map.put(key, value)
             |> CellDef.build() === %CellDef{border: value}
    end

    test "builds with provided configuration and sets :configuration" do
      value = %{custom_property: :something}
      key = :configuration

      assert Map.new()
             |> Map.put(key, value)
             |> CellDef.build() === %CellDef{configuration: value}
    end

    test "default values" do
      assert CellDef.build() === %CellDef{
               content: nil,
               wrap_text: nil,
               font: nil,
               align_vertical: nil,
               align_horizontal: nil,
               bold: nil,
               italic: nil,
               underline: nil,
               strike: nil,
               size: nil,
               color: nil,
               bg_color: nil,
               num_format: nil,
               datetime: nil,
               yyyymmdd: nil,
               border: nil,
               configuration: %{}
             }
    end
  end
end
