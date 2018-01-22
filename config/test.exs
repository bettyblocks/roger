use Mix.Config

config :roger,
  amqp: [
    host: "localhost",
    port: 5672
  ]

# Print only warnings and errors during test
config :logger, level: :warn
