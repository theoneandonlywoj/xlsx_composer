defmodule XLSXComposer.MixProject do
  use Mix.Project

  def project do
    [
      app: :xlsx_composer,
      version: "0.1.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases()
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
