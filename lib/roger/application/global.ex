defmodule Roger.Application.Global do
  @moduledoc """
  Coordinates the global Roger application state

  Each Roger application has a single place where global state is
  kept. Global state (and global coordination) is needed for the
  following things:

  - Job cancellation; when cancelling a job, we store the job ID
    globally; when the cancelled job is started, we check the job id
    against this list of cancelled ids.

  - Queue keys; some jobs dictate that they cannot be queued when
    there is already a job queued with an identical queue key; if so,
    the job fails to enqueue.

  - Execution keys; jobs which have the same execution key cannot be
    executed concurrently and need to wait on one another.

  - Pause states; it is globally stored which queues are currently
    paused.

  The per-application Global process stores all this information. It
  provides hooks to persist the information between application / node
  restarts. By default, the global state is loaded from and written to
  the filesystem, but it is possible to override the persister, like this:

      config :roger, Roger.Application.Global,
        persister: Your.PersisterModule

  The persister module must implement the
  `Roger.Application.Global.StatePersister` behaviour, which provides
  simple load and save functions.

  """

  use GenServer

  require Logger
  alias Roger.{Application, KeySet, System}
  alias Roger.Application.Global.State

  @persister_module Elixir.Application.get_env(:roger, __MODULE__, [])[:persister] || Roger.Application.Global.StatePersister.Stub

  def cancel_job(application_id, job_id) do
    GenServer.call(global_name(application_id), {:cancel, job_id})
  end

  def cancelled?(application_id, job_id, remove \\ nil) do
    GenServer.call(global_name(application_id), {:is_cancelled, job_id, remove})
  end

  def queued?(application_id, queue_key, add \\ nil) do
    GenServer.call(global_name(application_id), {:is_queued, queue_key, add})
  end

  def remove_queued(application_id, queue_key) do
    GenServer.call(global_name(application_id), {:remove_queued, queue_key})
  end

  def executing?(application_id, execution_key, add \\ nil) do
    GenServer.call(global_name(application_id), {:is_executing, execution_key, add})
  end

  def remove_executed(application_id, execution_key) do
    GenServer.call(global_name(application_id), {:remove_executed, execution_key})
  end

  @doc """
  Cluster-wide pausing of the given queue in the given application_id.
  """
  def queue_pause(application_id, queue) do
    GenServer.call(global_name(application_id), {:queue_pause, queue})
  end

  @doc """
  Cluster-wide pausing of the given queue in the given application_id.
  """
  def queue_resume(application_id, queue) do
    GenServer.call(global_name(application_id), {:queue_resume, queue})
  end

  def queue_get_paused(application_id) do
    GenServer.call(global_name(application_id), :queue_get_paused)
  end

  def global_name(id) when is_binary(id) do
    {:global, {:app_global, id}}
  end


  ## Server side

  @save_interval 1000

  def init([application_id]) do
    Process.send_after(self(), :save, @save_interval)
    :ok = @persister_module.init(application_id)
    {:ok, load(application_id)}
  end

  def handle_call({:cancel, job_id}, _from, state) do
    KeySet.add(state.cancel_set, job_id)
    System.cast(:cancel, job_id: job_id)
    {:reply, :ok, State.set_dirty(state)}
  end

  def handle_call({:is_cancelled, job_id, remove}, _from, state) do
    reply = KeySet.contains?(state.cancel_set, job_id)
    if reply and remove == :remove do
      KeySet.remove(state.cancel_set, job_id)
      {:reply, reply, State.set_dirty(state)}
    else
      {:reply, reply, state}
    end
  end

  def handle_call({:is_queued, queue_key, add}, _from, state) do
    reply = KeySet.contains?(state.queue_set, queue_key)
    if !reply and add == :add do
      KeySet.add(state.queue_set, queue_key)
      {:reply, reply, State.set_dirty(state)}
    else
      {:reply, reply, state}
    end
  end

  def handle_call({:remove_queued, queue_key}, _from, state) do
    reply = KeySet.remove(state.queue_set, queue_key)
    {:reply, reply, State.set_dirty(state)}
  end

  def handle_call({:is_executing, execute_key, add}, _from, state) do
    reply = KeySet.contains?(state.execute_set, execute_key)
    if !reply and add == :add do
      KeySet.add(state.execute_set, execute_key)
      {:reply, reply, State.set_dirty(state)}
    else
      {:reply, reply, state}
    end
  end

  def handle_call({:remove_executed, execute_key}, _from, state) do
    reply = KeySet.remove(state.execute_set, execute_key)
    {:reply, reply, State.set_dirty(state)}
  end

  ## queue pause / resume

  def handle_call({:queue_pause, queue}, _from, state) do
    System.cast(:queue_pause, queue: queue, app_id: state.application_id)
    {:reply, :ok, %{state | paused: MapSet.put(state.paused, queue), dirty: true}}
  end

  def handle_call({:queue_resume, queue}, _from, state) do
    System.cast(:queue_resume, queue: queue, app_id: state.application_id)
    {:reply, :ok, %{state | paused: MapSet.delete(state.paused, queue), dirty: true}}
  end

  def handle_call(:queue_get_paused, _from, state) do
    {:reply, state.paused, state}
  end

  ## persistence

  def handle_info(:save, state) do
    Process.send_after(self(), :save, @save_interval)
    {:noreply, save(state)}
  end

  defp load(application_id) do
    case @persister_module.load(application_id) do
      {:ok, data} ->
        state = State.deserialize(data)
        %State{state | application_id: application_id}
      {:error, _} ->
        State.new(application_id)
    end
  end

  defp save(%State{dirty: false} = state) do
    state
  end
  defp save(state) do
    @persister_module.store(state.application_id, State.serialize(state))
    %State{state | dirty: false}
  end

end
