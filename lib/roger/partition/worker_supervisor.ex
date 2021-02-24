defmodule Roger.Partition.WorkerSupervisor do
  @moduledoc """
  The per-partition supervisor for job workers.

  Workers processes are spawned on-demand from the
  `Roger.Partition.Consumer` process as soon as a job is ready to be
  processed.

  """

  use Supervisor

  alias Roger.GProc

  @doc false
  def start_link(partition) do
    Supervisor.start_link(__MODULE__, [], name: GProc.via(name(partition)))
  end

  defp name(id) do
    {:app_worker_supervisor, id}
  end

  def init([]) do
    children = [
      worker(Roger.Partition.Worker, [], restart: :transient)
    ]

    supervise(children, strategy: :simple_one_for_one)
  end

  @doc """
  Start a job worker process in the supervisor
  """
  def start_child(partition, channel, payload, meta) do
    Supervisor.start_child(GProc.via(name(partition)), [partition, channel, payload, meta])
  end
end
