defmodule Roger.Partition.ContainingSupervisor do
  @moduledoc """
  The supervisor hierarchy for a single partition
  """

  use Supervisor, restart: :transient

  alias Roger.GProc

  def start_link([partition]) do
    Supervisor.start_link(__MODULE__, [partition], name: GProc.via(name(partition)))
  end

  def stop(partition) do
    Roger.PartitionSupervisor.stop_child(GProc.whereis(name(partition)))
  end

  defp name(id) do
    {:app_supervisor, id}
  end

  def init([partition]) do
    children = [
      {Roger.Partition.WorkerSupervisor, partition},
      {Roger.Partition.Consumer, partition}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
