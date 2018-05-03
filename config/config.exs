use Mix.Config

config :lager, :error_logger_redirect, false

import_config "#{Mix.env}.exs"
