use Mix.Config

config :amqp,
  connections: [
    roger_conn: [
      host: "127.0.0.1",
      port: 5672,
      username: "guest",
      password: "guest"
    ]
  ],
  channels: [
    send_channel: [connection: :roger_conn]
  ]

config :roger,
  connection_name: :roger_conn,
  channel_name: :send_channel

# Print only warnings and errors during test
config :logger, level: :warn
