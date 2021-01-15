use Mix.Config

# config :lager, :error_logger_redirect, false
config :sasl, :errlog_type, :debug
import_config "#{Mix.env()}.exs"
