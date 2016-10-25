defmodule Roger.Application.ContainingSupervisor do
  @moduledoc """
  The supervisor hierarchy for a single application
  """

  use Supervisor

  alias Roger.{GProc, Application}

  def start_link(application) do
    Supervisor.start_link(__MODULE__, [application], name: GProc.via(name(application)))
  end

  defp name(%Application{id: id}) do
    {:app_supervisor, id}
  end

  def init([application]) do

    children = [
      supervisor(Roger.Application.WorkerSupervisor, [application], restart: :permanent),
      worker(Roger.Application.Consumer, [application], restart: :permanent),
    ]

    supervise(children, strategy: :one_for_one)
  end




end
