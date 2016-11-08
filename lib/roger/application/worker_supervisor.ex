defmodule Roger.Application.WorkerSupervisor do
  @moduledoc """
  The per-application supervisor for job workers.

  Workers processes are spawned on-demand from the
  `Roger.Application.Consumer` process as soon as a job is ready to be
  processed.

  """

  use Supervisor

  alias Roger.GProc

  @doc false
  def start_link(application) do
    Supervisor.start_link(__MODULE__, [], name: GProc.via(name(application)))
  end

  defp name(id) do
    {:app_worker_supervisor, id}
  end

  def init([]) do
    children = [
      worker(Roger.Application.Worker, [], restart: :transient)
    ]

    supervise(children, strategy: :simple_one_for_one)
  end

  @doc """
  Start a job worker process in the supervisor
  """
  def start_child(application, channel, payload, meta) do
    Supervisor.start_child(GProc.via(name(application)), [application, channel, payload, meta])
  end

end
