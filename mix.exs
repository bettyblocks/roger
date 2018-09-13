defmodule Roger.Mixfile do
  use Mix.Project

  def project do
    [app: :roger,
     version: "2.2.0",
     elixir: ">= 1.5.1",
     elixirc_paths: elixirc_paths(Mix.env),
     build_embedded: Mix.env == :prod,
     start_permanent: Mix.env == :prod,
     description: description(),
     package: package(),
     source_url: "https://github.com/bettyblocks/roger",
     homepage_url: "https://github.com/bettyblocks/roger",
     deps: deps(),
     docs: [extras: ["docs/overview.md", "docs/configuration.md"]]
    ]
  end

  defp elixirc_paths(:prod), do: ["lib"]
  defp elixirc_paths(_),     do: ["lib", "test/support", "integration_test"]

  defp description do
    "RabbitMQ-backed background job processing system"
  end

  defp package do
    %{files: ["lib", "mix.exs",
              "docs/*.md", "LICENSE"],
      maintainers: ["Arjan Scherpenisse", "Peter Arentsen"],
      licenses: ["MIT"],
      links: %{"GitHub" => "https://github.com/bettyblocks/roger"}}
  end

  # Configuration for the OTP application
  def application do
    [extra_applications: [:logger],
     mod: {Roger, []}]
  end

  # Dependencies
  defp deps do
    [
      {:amqp, "~> 0.3 or ~> 1.0"},
      {:jsx, "~> 2.8"},
      {:singleton, "~> 1.0"},
      {:gproc, "~> 0.6"},
      {:poison, "~> 2.1 or ~> 3.0 or ~> 4.0"},
      {:ex_doc, "~> 0.12", only: :dev},
      {:inch_ex, ">= 0.0.0", only: :docs}
    ]
  end
end
