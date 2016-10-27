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

  def cancelled?(application, job_id, remove \\ nil) do
    GenServer.call(global_name(application), {:is_cancelled, job_id, remove})
  end

  def queued?(application, queue_key, add \\ nil) do
    GenServer.call(global_name(application), {:is_queued, queue_key, add})
  end

  def remove_queued(application, queue_key) do
    GenServer.call(global_name(application), {:remove_queued, queue_key})
  end

  def executing?(application, execution_key, add \\ nil) do
    GenServer.call(global_name(application), {:is_executing, execution_key, add})
  end

  def remove_executed(application, execution_key) do
    GenServer.call(global_name(application), {:remove_executed, execution_key})
  end

  defp global_name(%Application{id: id}) do
    {:global, {:app_state_manager, id}}
  end


  ## Server side

  defmodule State do
    defstruct application: nil, cancel_set: nil, queue_set: nil, execute_set: nil
  end

  def init([application]) do
    {:ok, cancel_set} = KeySet.start_link
    {:ok, queue_set} = KeySet.start_link
    {:ok, execute_set} = KeySet.start_link
    state = %State{
      application: application,
      cancel_set: cancel_set,
      execute_set: execute_set,
      queue_set: queue_set}
    {:ok, state}
  end

  def handle_call({:cancel, job_id}, _from, state) do
    KeySet.add(state.cancel_set, job_id)

    # Cancel any running jobs
    for {pid, _value} <- GProc.find_properties(Worker.name(job_id)) do
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

  def handle_call({:is_queued, queue_key, add}, _from, state) do
    reply = KeySet.contains?(state.queue_set, queue_key)
    if !reply and add == :add do
      KeySet.add(state.queue_set, queue_key)
    end
    {:reply, reply, state}
  end

  def handle_call({:remove_queued, queue_key}, _from, state) do
    reply = KeySet.remove(state.queue_set, queue_key)
    {:reply, reply, state}
  end

  def handle_call({:is_executing, execute_key, add}, _from, state) do
    reply = KeySet.contains?(state.execute_set, execute_key)
    if !reply and add == :add do
      KeySet.add(state.execute_set, execute_key)
    end
    {:reply, reply, state}
  end

  def handle_call({:remove_executed, execute_key}, _from, state) do
    reply = KeySet.remove(state.execute_set, execute_key)
    {:reply, reply, state}
  end

end
