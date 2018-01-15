defmodule Roger do
  @moduledoc """
  The OTP partition's entrypoint and top-level supervisor
  """

  use Application

  require Logger

  def start(_, _) do
    if Application.get_env(:roger, :start_on_application, true) do
      start_link()
    else
      Supervisor.start_link([], strategy: :one_for_one)
    end
  end

  def start_link(_opts \\ []) do
    import Supervisor.Spec, warn: false

    amqp_config = Application.get_env(:roger, :amqp)

    children = [
      worker(Roger.AMQPClient, [amqp_config]),
      worker(Roger.System, []),
      supervisor(Roger.PartitionSupervisor, []),
      worker(Roger.Partition, []),
      worker(Roger.ShutdownHandler, [])
    ]

    opts = [strategy: :one_for_one, name: Roger.Supervisor]
    Supervisor.start_link(children, opts)
  end

  @doc """
  Returns the current time in milliseconds.
  """
  def now() do
    :os.system_time(1000)
  end

end
