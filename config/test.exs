use Mix.Config

config :roger,
  amqp: [
    host: "127.0.0.1",
    port: 5672,
    username: "user",
    password: "password",
    virtual_host: "/vhost"
  ]

# Print only warnings and errors during test
# config :logger, level: :warn
