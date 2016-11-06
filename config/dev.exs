use Mix.Config

config :roger, Roger.AMQPClient,
  host: "localhost",
  port: 5672

config :roger, :applications,
  example: [default: 10, other: 2]
