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

config :roger, :partitions, example: [default: 10, other: 2]
