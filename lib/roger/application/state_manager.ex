defmodule Roger.Application.StateManager do
  @moduledoc """
  Global application state
  """

  use GenServer

  require Logger
  alias Roger.{GProc, Application, KeySet, Application.Worker}

  def start_link(application) do
    GenServer.start_link(__MODULE__, [application], name: global_name(application))
  end

  def cancel_job(application, job_id) do
    GenServer.call(global_name(application), {:cancel, job_id})
  end

  def is_cancelled?(application, job_id, remove \\ nil) do
    GenServer.call(global_name(application), {:is_cancelled, job_id, remove})
  end

  defp global_name(%Application{id: id}) do
    {:global, {:app_state_manager, id}}
  end


  ## Server side

  defmodule State do
    defstruct application: nil, cancel_set: nil
  end

  def init([application]) do
    {:ok, cancel_set} = KeySet.start_link
    state = %State{
      application: application,
      cancel_set: cancel_set}
    {:ok, state}
  end

  def handle_call({:cancel, job_id}, _from, state) do
    KeySet.add(state.cancel_set, job_id)

    pid = GProc.whereis(Worker.name(job_id))
    if is_pid(pid) and Process.alive?(pid) do
      Process.exit(pid, :exit)
    end

    {:reply, :ok, state}
  end

  def handle_call({:is_cancelled, job_id, remove}, _from, state) do
    reply = KeySet.contains?(state.cancel_set, job_id)
    if reply and remove == :remove do
      KeySet.remove(state.cancel_set, job_id)
    end
    {:reply, reply, state}
  end

end
