defmodule XLSXComposer.BorderDefTest do
  use ExUnit.Case, async: true

  alias XLSXComposer.BorderDef
  alias XLSXComposer.BorderDef.Side

  describe "Side.new/1" do
    test "defaults properties to nil and stores supplied properties" do
      assert Side.new() === %Side{style: nil, color: nil}

      assert Side.new(%{style: :thin, color: "#cc3311"}) ===
               %Side{style: :thin, color: "#cc3311"}
    end
  end

  describe "new/1" do
    test "defaults every field to nil" do
      assert BorderDef.new() === %BorderDef{
               left: nil,
               right: nil,
               top: nil,
               bottom: nil,
               diagonal: nil,
               diagonal_up: nil,
               diagonal_down: nil,
               preset: nil
             }
    end

    test "stores explicit sides and flags" do
      side = Side.new(%{style: :double, color: "#cc3311"})

      assert BorderDef.new(%{
               left: side,
               right: side,
               top: side,
               bottom: side,
               diagonal: side,
               diagonal_up: true,
               diagonal_down: false
             }) === %BorderDef{
               left: side,
               right: side,
               top: side,
               bottom: side,
               diagonal: side,
               diagonal_up: true,
               diagonal_down: false
             }
    end

    test "all expands only cardinal sides and explicit sides override it" do
      all = Side.new(%{style: :thin})
      top = Side.new(%{style: :double})

      assert BorderDef.new(%{all: all, top: top}) ===
               %BorderDef{left: all, right: all, top: top, bottom: all}
    end

    test "explicit sides override all, and all overrides the stored preset" do
      all = Side.new(%{style: :medium})
      top = Side.new(%{style: :double})

      assert BorderDef.new(%{preset: :thin, all: all, top: top}) ===
               %BorderDef{left: all, right: all, top: top, bottom: all, preset: :thin}
    end

    test "presets expand cardinal sides without a diagonal" do
      for style <- [:thin, :medium, :thick, :dashed, :dotted, :double] do
        side = Side.new(%{style: style})

        assert BorderDef.new(%{preset: style}) ===
                 %BorderDef{left: side, right: side, top: side, bottom: side, preset: style}
      end
    end
  end

  describe "to_elixlsx/1" do
    test "nil and empty definitions emit no keywords" do
      assert BorderDef.to_elixlsx(nil) === []
      assert BorderDef.to_elixlsx(%BorderDef{}) === []
    end

    test "emits sides in cardinal then diagonal order, with flags last" do
      side = Side.new(%{style: :thin, color: "#cc3311"})

      assert BorderDef.new(%{all: side, diagonal: side, diagonal_up: true, diagonal_down: true})
             |> BorderDef.to_elixlsx() === [
               left: [style: :thin, color: "#cc3311"],
               right: [style: :thin, color: "#cc3311"],
               top: [style: :thin, color: "#cc3311"],
               bottom: [style: :thin, color: "#cc3311"],
               diagonal: [style: :thin, color: "#cc3311"],
               diagonal_up: true,
               diagonal_down: true
             ]
    end

    test "omits empty sides and unset properties, retaining color-only sides" do
      border = %BorderDef{
        left: %Side{},
        right: %Side{color: "#cc3311"},
        top: %Side{style: :thin},
        diagonal: %Side{},
        diagonal_up: false,
        diagonal_down: nil
      }

      assert BorderDef.to_elixlsx(border) === [right: [color: "#cc3311"], top: [style: :thin]]
    end

    test "emits each diagonal flag only when true" do
      assert BorderDef.to_elixlsx(%BorderDef{diagonal_up: true, diagonal_down: false}) ===
               [diagonal_up: true]

      assert BorderDef.to_elixlsx(%BorderDef{diagonal_up: nil, diagonal_down: true}) ===
               [diagonal_down: true]
    end

    test "constructed and direct presets convert to the same four sides" do
      expected = [
        left: [style: :thin],
        right: [style: :thin],
        top: [style: :thin],
        bottom: [style: :thin]
      ]

      assert BorderDef.to_elixlsx(BorderDef.new(%{preset: :thin})) === expected
      assert BorderDef.to_elixlsx(%BorderDef{preset: :thin}) === expected
    end
  end

  describe "from_keyword/1 and normalize/1" do
    test "nil stays nil and an empty keyword becomes an empty border" do
      assert BorderDef.from_keyword(nil) === nil
      assert BorderDef.normalize(nil) === nil
      assert BorderDef.from_keyword([]) === %BorderDef{}
      assert BorderDef.normalize([]) === %BorderDef{}
    end

    test "raw sides and flags convert to typed fields and round-trip" do
      keyword = [
        left: [style: :thin],
        right: [color: "#cc3311"],
        top: [style: :medium],
        bottom: [style: :double, color: "#cc3311"],
        diagonal: [style: :dotted],
        diagonal_up: true,
        diagonal_down: true
      ]

      expected = %BorderDef{
        left: %Side{style: :thin},
        right: %Side{color: "#cc3311"},
        top: %Side{style: :medium},
        bottom: %Side{style: :double, color: "#cc3311"},
        diagonal: %Side{style: :dotted},
        diagonal_up: true,
        diagonal_down: true
      }

      assert BorderDef.from_keyword(keyword) === expected
      assert BorderDef.normalize(keyword) === expected
      assert BorderDef.to_elixlsx(expected) === keyword
    end

    test "normalization expands a preset, preserves overrides and diagonals, and is idempotent" do
      top = %Side{color: "#cc3311"}
      diagonal = %Side{style: :double}
      border = %BorderDef{preset: :thin, top: top, diagonal: diagonal, diagonal_up: false}
      normalized = BorderDef.normalize(border)

      assert normalized === %BorderDef{
               left: %Side{style: :thin},
               right: %Side{style: :thin},
               top: top,
               bottom: %Side{style: :thin},
               diagonal: diagonal,
               diagonal_up: false
             }

      assert BorderDef.normalize(normalized) === normalized
      assert BorderDef.to_elixlsx(border) === BorderDef.to_elixlsx(normalized)
    end
  end

  describe "merge/2" do
    test "nil operands are normalized without inventing sides" do
      assert BorderDef.merge(nil, nil) === nil

      for {first, second} <- [{nil, [top: [style: :thin]]}, {[top: [style: :thin]], nil}] do
        assert BorderDef.merge(first, second) === %BorderDef{top: %Side{style: :thin}}
      end

      assert BorderDef.merge(%BorderDef{preset: :thin}, nil) ===
               BorderDef.normalize(%BorderDef{preset: :thin})
    end

    test "first sides win as whole sides, missing sides fill, and diagonal flags use OR" do
      first = %BorderDef{
        left: %Side{style: :double},
        top: %Side{color: "#cc3311"},
        diagonal: %Side{style: :dotted},
        diagonal_up: false,
        diagonal_down: true
      }

      second = [
        left: [style: :thin, color: "#000000"],
        right: [style: :thin],
        top: [style: :thin],
        bottom: [style: :thin],
        diagonal: [style: :thin],
        diagonal_up: true,
        diagonal_down: false
      ]

      assert BorderDef.merge(first, second) === %BorderDef{
               left: first.left,
               right: %Side{style: :thin},
               top: first.top,
               bottom: %Side{style: :thin},
               diagonal: first.diagonal,
               diagonal_up: true,
               diagonal_down: true
             }
    end

    test "presets are normalized before merging without implying a diagonal" do
      first = %BorderDef{preset: :thin}
      second = %BorderDef{left: %Side{style: :double}, diagonal: %Side{style: :dotted}}

      assert BorderDef.merge(first, second) === %BorderDef{
               left: %Side{style: :thin},
               right: %Side{style: :thin},
               top: %Side{style: :thin},
               bottom: %Side{style: :thin},
               diagonal: second.diagonal
             }
    end
  end
end
