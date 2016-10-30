defmodule Roger.ApplicationSupervisor do
  @moduledoc """
  The supervisor for all applications.
  """

  use Supervisor

  def start_link() do
    Supervisor.start_link(__MODULE__, [], name: __MODULE__)
  end

  def init([]) do
    children = [
      supervisor(Roger.Application.ContainingSupervisor, [], restart: :transient)
    ]
    supervise(children, strategy: :simple_one_for_one)
  end

  def start_child(application) do
    Supervisor.start_child(__MODULE__, [application])
  end

end
