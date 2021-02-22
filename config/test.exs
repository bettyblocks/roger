use Mix.Config

config :amqp,
  connections: [
    roger_conn: [
      host: "localhost",
      port: 5672
    ]
  ],
  channels: [
    send_channel: [connection: :roger_conn]
  ]

# Print only warnings and errors during test
config :logger, level: :warn
