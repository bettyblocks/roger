import Config

# Overridable so the suite can also run against a RabbitMQ that does not have
# the default guest user and vhost, without having to edit this file.
config :amqp,
  connections: [
    roger_conn: [
      host: System.get_env("RABBITMQ_HOST", "127.0.0.1"),
      port: String.to_integer(System.get_env("RABBITMQ_PORT", "5672")),
      username: System.get_env("RABBITMQ_USERNAME", "guest"),
      password: System.get_env("RABBITMQ_PASSWORD", "guest"),
      virtual_host: System.get_env("RABBITMQ_VHOST", "/")
    ]
  ],
  channels: [
    send_channel: [connection: :roger_conn]
  ]

config :roger,
  connection_name: :roger_conn,
  channel_name: :send_channel

# Print only warnings and errors during test
config :logger, level: :warning
