defmodule Roger.Application.Global do
  @moduledoc """
  Global application state
  """

  use GenServer

  require Logger
  alias Roger.{Application, KeySet, System}
  alias Roger.Application.Global.State

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

  @doc """
  Cluster-wide pausing of the given queue in the given application.
  """
  def queue_pause(application, queue) do
    GenServer.call(global_name(application), {:queue_pause, queue})
  end

  @doc """
  Cluster-wide pausing of the given queue in the given application.
  """
  def queue_resume(application, queue) do
    GenServer.call(global_name(application), {:queue_resume, queue})
  end

  def queue_get_paused(application) do
    GenServer.call(global_name(application), :queue_get_paused)
  end

  def global_name(%Application{id: id}) do
    global_name(id)
  end
  def global_name(id) when is_binary(id) do
    {:global, {:app_global, id}}
  end


  ## Server side

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
    System.cast(:cancel, job_id: job_id)
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

  def handle_call({:queue_pause, queue}, _from, state) do
    System.cast(:queue_pause, queue: queue, app_id: state.application.id)
    {:reply, :ok, %{state | paused: MapSet.put(state.paused, queue)}}
  end

  def handle_call({:queue_resume, queue}, _from, state) do
    System.cast(:queue_resume, queue: queue, app_id: state.application.id)
    {:reply, :ok, %{state | paused: MapSet.delete(state.paused, queue)}}
  end

  def handle_call(:queue_get_paused, _from, state) do
    {:reply, state.paused, state}
  end

end
