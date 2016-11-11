defmodule Roger.Partition.ContainingSupervisor do
  @moduledoc """
  The supervisor hierarchy for a single partition
  """

  use Supervisor

  alias Roger.GProc

  def start_link(partition) do
    Supervisor.start_link(__MODULE__, [partition], name: GProc.via(name(partition)))
  end

  defp name(id) do
    {:app_supervisor, id}
  end

  def init([partition]) do

    children = [
      supervisor(Roger.Partition.WorkerSupervisor, [partition], restart: :permanent),
      worker(Roger.Partition.Consumer, [partition], restart: :permanent),
    ]

    supervise(children, strategy: :one_for_one)
  end

end
