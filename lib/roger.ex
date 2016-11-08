defmodule Roger do
  @moduledoc """
  The OTP application's entrypoint and top-level supervisor
  """

  use Application

  require Logger

  def start(_, _) do
    import Supervisor.Spec, warn: false

    amqp_config = Application.get_env(:roger, Roger.AMQPClient)

    children = [
      worker(Roger.AMQPClient, [amqp_config]),
      worker(Roger.System, []),
      supervisor(Roger.ApplicationSupervisor, []),
      worker(Roger.Application, []),
    ]

    opts = [strategy: :one_for_one, name: Roger.Supervisor]
    Supervisor.start_link(children, opts)
  end

  @doc false
  def prep_stop(_) do
    Roger.AMQPClient.close()
  end

  @doc """
  Returns the current time in milliseconds.
  """
  def now() do
    :os.system_time(1000)
  end

end
