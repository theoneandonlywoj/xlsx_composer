defmodule XLSXComposer.MixProject do
  use Mix.Project

  @external_resource "VERSION"
  @version __DIR__ |> Path.join("VERSION") |> File.read!() |> String.trim()

  def project do
    [
      app: :xlsx_composer,
      version: @version,
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases(),
      description: description(),
      package: package(),
      name: "xlsx_composer",
      source_url: "https://github.com/theoneandonlywoj/xlsx_composer",
      dialyzer: [plt_file: {:no_warn, "priv/plts/dialyzer.plt"}]
    ]
  end

  defp description() do
    "Wrapper around Elixlsx to create .xlsx files in a performant, yet declarative way."
  end

  defp package() do
    [
      name: "xlsx_composer",
      licenses: ["Apache-2.0"],
      links: %{"GitHub" => "https://github.com/theoneandonlywoj/xlsx_composer"},
      files: ~w(lib .formatter.exs mix.exs VERSION README* LICENSE* CHANGELOG*)
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:ex_doc, ">= 0.0.0", only: :dev, runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:elixlsx, "~> 0.6.0"}
    ]
  end

  defp aliases() do
    [
      quality: [
        "compile --warnings-as-errors",
        "format --check-formatted",
        "credo --strict",
        "dialyzer"
      ]
    ]
  end
end
