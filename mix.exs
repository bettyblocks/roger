defmodule Roger.Mixfile do
  use Mix.Project

  def project do
    [
      app: :roger,
      version: "3.1.1",
      elixir: ">= 1.9.0",
      elixirc_paths: elixirc_paths(Mix.env()),
      build_embedded: Mix.env() == :prod,
      start_permanent: Mix.env() == :prod,
      description: description(),
      package: package(),
      source_url: "https://github.com/bettyblocks/roger",
      homepage_url: "https://github.com/bettyblocks/roger",
      dialyzer: [
        plt_file: {:no_warn, "priv/plts/dialyzer.plt"}
      ],
      deps: deps(),
      docs: [extras: ["docs/overview.md", "docs/configuration.md"]]
    ]
  end

  defp elixirc_paths(:prod), do: ["lib"]
  defp elixirc_paths(_), do: ["lib", "test/support", "integration_test"]

  defp description do
    "RabbitMQ-backed background job processing system"
  end

  defp package do
    %{
      files: ["lib", "mix.exs", "docs/*.md", "LICENSE"],
      maintainers: ["Arjan Scherpenisse", "Peter Arentsen"],
      licenses: ["MIT"],
      links: %{"GitHub" => "https://github.com/bettyblocks/roger"}
    }
  end

  # Configuration for the OTP application
  def application do
    [extra_applications: [:logger], mod: {Roger, []}]
  end

  # Dependencies
  defp deps do
    [
      {:amqp, "~> 2.0 or ~> 3.0"},
      {:dialyxir, "~> 1.0", only: [:dev, :test], runtime: false},
      {:singleton, "~> 1.0"},
      {:gproc, "~> 0.6"},
      {:jason, "~> 1.3"},
      {:ex_doc, "~> 0.12", only: :dev},
      {:inch_ex, ">= 0.0.0", only: :docs},
      {:credo, ">= 0.0.0", only: :dev}
    ]
  end
end
