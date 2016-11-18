defmodule Roger.Mixfile do
  use Mix.Project

  def project do
    [app: :roger,
     version: "1.0.0-beta3",
     elixir: "~> 1.3",
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
      maintainers: ["Arjan Scherpenisse"],
      licenses: ["MIT"],
      links: %{"GitHub" => "https://github.com/bettyblocks/roger"}}
  end

  # Configuration for the OTP application
  def application do
    [applications: [:amqp, :gproc, :logger, :singleton],
     mod: {Roger, []}]
  end

  # Dependencies
  defp deps do
    [
      {:amqp, "~> 0.1.5"},
      {:amqp_client, github: "jbrisbin/amqp_client", tag: "rabbitmq-3.6.2", override: true},
      {:singleton, "~> 1.0"},
      {:gproc, "~> 0.6.1"},
      {:poison, "~> 2.1"},

      {:ex_doc, "~> 0.12", only: :dev}
    ]
  end
end
