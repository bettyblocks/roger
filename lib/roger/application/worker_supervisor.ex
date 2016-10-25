defmodule Roger.Application.WorkerSupervisor do
  @moduledoc """
  The per-application supervisor for job workers
  """

  use Supervisor

  alias Roger.{GProc, Application}

  def start_link(application) do
    Supervisor.start_link(__MODULE__, [], name: GProc.via(name(application)))
  end

  defp name(%Application{id: id}) do
    {:app_worker_supervisor, id}
  end


  def init([]) do
    children = [
      worker(Roger.Application.Worker, [], restart: :transient)
    ]

    supervise(children, strategy: :simple_one_for_one)
  end

  def start_child(application, payload, meta) do
    Supervisor.start_child(GProc.via(name(application)), [application, payload, meta])
  end

end
