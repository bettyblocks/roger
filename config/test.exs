use Mix.Config

config :roger, Roger.AMQPClient,
  host: "localhost",
  port: 5672

# Print only warnings and errors during test
config :logger, level: :warn
