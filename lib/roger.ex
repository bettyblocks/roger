defmodule Roger do

  use Application

  require Logger

  def start(_, _) do
    import Supervisor.Spec, warn: false

    amqp_config = Application.get_env(:roger, Roger.AMQPClient)

    children = [
      worker(Roger.AMQPClient, [amqp_config]),
      supervisor(Roger.ApplicationSupervisor, []),
    ]

    opts = [strategy: :one_for_one, name: Roger.Supervisor]
    Supervisor.start_link(children, opts)
  end


end
