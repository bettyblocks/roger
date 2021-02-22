defmodule Roger.Partition.WorkerSupervisor do
  @moduledoc """
  The per-partition supervisor for job workers.

  Workers processes are spawned on-demand from the
  `Roger.Partition.Consumer` process as soon as a job is ready to be
  processed.

  """

  use DynamicSupervisor, restart: :permanent

  alias Roger.GProc

  @doc false
  def start_link(partition) do
    DynamicSupervisor.start_link(__MODULE__, [], name: GProc.via(name(partition)))
  end

  defp name(id) do
    {:app_worker_supervisor, id}
  end

  @impl true
  def init([]) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  @doc """
  Start a job worker process in the supervisor
  """
  def start_child(partition, channel, payload, meta) do
    DynamicSupervisor.start_child(
      GProc.via(name(partition)),
      {Roger.Partition.Worker, [partition, channel, payload, meta]}
    )
  end
end
