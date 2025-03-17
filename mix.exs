defmodule XLSXComposer.MixProject do
  use Mix.Project

  def project do
    [
      app: :xlsx_composer,
      version: "0.2.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases(),
      description: description(),
      package: package(),
      deps: deps(),
      name: "xlsx_composer",
      source_url: "https://github.com/theoneandonlywoj/xlsx_composer"
    ]
  end

  defp description() do
    "Wrapper around Elixlsx to create .xlsx files in a performant, yet declarative way."
  end

  defp package() do
    [
      name: "xlsx_composer",
      licenses: ["Apache-2.0"],
      links: %{"GitHub" => "https://github.com/theoneandonlywoj/xlsx_composer"}
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
      quality: ["format --check-formatted", "credo --strict", "dialyzer"]
    ]
  end
end
