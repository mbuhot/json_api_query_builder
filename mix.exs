defmodule JsonApiQueryBuilder.Mixfile do
  use Mix.Project

  @version "1.0.2"

  def project do
    [
      app: :json_api_query_builder,
      version: @version,
      elixir: "~> 1.5",
      start_permanent: Mix.env == :prod,
      deps: deps(),
      description: "Build Ecto queries from JSON-API requests",
      package: package(),

      #Docs
      source_url: "https://github.com/mbuhot/json_api_query_builder",
      homepage_url: "https://github.com/mbuhot/json_api_query_builder",
      docs: [extras: ["README.md"], main: "readme", source_ref: "v#{@version}"]
    ]
  end

  defp package do
    [maintainers: ["Michael Buhot"],
     licenses: ["MIT"],
     links: %{"Github" => "https://github.com/mbuhot/json_api_query_builder"}]
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
      {:ecto, "~> 3.5"},
      {:dialyxir, "~> 1.0", only: :dev, runtime: false},
      {:ex_doc, "~> 0.22", only: :dev, runtime: false},
      {:inch_ex, "~> 2.0", only: :dev, runtime: false},
      {:credo, "~> 1.4", only: :dev, runtime: false}
    ]
  end
end
