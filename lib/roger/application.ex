defmodule Roger.Application do
  @moduledoc """
  A structure which defines a single roger "application".

  Roger implements multi-tenancy by dividing all its work between
  different Applications. (this name might be confusing - an OTP
  application is something different!)

  Each application has a unique, stable ID, a name and a list which
  defines its queues. each queue is defined by its type (an atom) and
  a max_workers value which sets the concurrency level.

  """

  @type t :: %__MODULE__{}

  defstruct id: nil, name: nil, queues: []

  alias Roger.Application.{StateManager, Consumer}

  def start(%__MODULE__{} = application) do
    # make sure a statemanager instance is running
    Singleton.start_child(StateManager, [application], {:app_state_manager, application.id})
    # start application supervision tree
    case Roger.ApplicationSupervisor.start_child(application) do
      {:ok, pid} ->
        {:ok, pid}
      {:error, {:already_started, pid}} ->
        :ok = Consumer.reconfigure(application)
        {:ok, pid}
    end
  end

  def running_applications do
    for {:app_supervisor, id} <- Roger.GProc.find_names({:app_supervisor, :_}) do
      %__MODULE__{id: id, queues: Roger.Application.Consumer.get_queues(id)}
    end
  end

  def start_all(apps) do
    apps
    |> Enum.map(fn({id, queues}) ->
      queues = (for q <- queues, do: Roger.Queue.define(q))
      app = %__MODULE__{id: "#{id}", queues: queues}
      {:ok, _} = start(app)
    end)
  end

end
