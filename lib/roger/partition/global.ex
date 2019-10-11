defmodule Roger.Partition.Global do
  @moduledoc """
  Coordinates the global Roger partition state

  Each Roger partition has a single place where global state is
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

  The per-partition Global process stores all this information. It
  provides hooks to persist the information between partition / node
  restarts. By default, the global state is loaded from and written to
  the filesystem, but it is possible to override the persister, like this:

      config :roger,
        persister: Your.PersisterModule

  The persister module must implement the
  `Roger.Partition.Global.StatePersister` behaviour, which provides
  simple load and save functions.

  """

  use GenServer

  require Logger
  alias Roger.{KeySet, System}
  alias Roger.Partition.Global.State

  @doc """
  Mark a job id as cancelled.

  This does not check for the validity of the job id. The job will not
  be removed from the queue, but instead will be removed as soon as
  it's dequeued.

  When a job is currently executing, the process of a running job will
  be killed.
  """
  @spec cancel_job(partition_id :: String.t, job_id :: String.t) :: :ok
  def cancel_job(partition_id, job_id) do
    partition_call(partition_id, {:cancel, job_id})
  end

  @doc """
  Check whether a given job id has been marked cancelled
  """
  @spec cancelled?(partition_id :: String.t, job_id :: String.t) :: boolean
  @spec cancelled?(partition_id :: String.t, job_id :: String.t, remove :: :remove) :: boolean
  def cancelled?(partition_id, job_id, remove \\ nil) do
    partition_call(partition_id, {:is_cancelled, job_id, remove})
  end

  @doc """
  Check whether a given queue key has been marked enqueued
  """
  @spec queued?(partition_id :: String.t, queue_key :: String.t) :: boolean
  @spec queued?(partition_id :: String.t, queue_key :: String.t, add :: :add) :: boolean
  def queued?(partition_id, queue_key, add \\ nil) do
    partition_call(partition_id, {:is_queued, queue_key, add})
  end

  @doc """
  Remove a given queue key
  """
  @spec remove_queued(partition_id :: String.t, queue_key :: String.t) :: :ok
  def remove_queued(partition_id, queue_key) do
    partition_call(partition_id, {:remove_queued, queue_key})
  end

  @doc """
  Check whether a given execution key has been set
  """
  @spec executing?(partition_id :: String.t, execution_key :: String.t) :: boolean
  @spec executing?(partition_id :: String.t, execution_key :: String.t, add :: :add) :: boolean
  def executing?(partition_id, execution_key, add \\ nil) do
    partition_call(partition_id, {:is_executing, execution_key, add})
  end

  @doc """
  Remove the given execution key
  """
  @spec remove_executed(partition_id :: String.t, execution_key :: String.t) :: :ok
  def remove_executed(partition_id, execution_key) do
    partition_call(partition_id, {:remove_executed, execution_key})
  end

  @doc """
  Cluster-wide pausing of the given queue in the given partition_id.
  """
  @spec queue_pause(partition_id :: String.t, queue :: any) :: :ok
  def queue_pause(partition_id, queue) do
    partition_call(partition_id, {:queue_pause, queue})
  end

  @doc """
  Cluster-wide pausing of the given queue in the given partition_id.
  """
  @spec queue_resume(partition_id :: String.t, queue :: any) :: :ok
  def queue_resume(partition_id, queue) do
    partition_call(partition_id, {:queue_resume, queue})
  end

  @doc """
  Get the set of paused queues for the given partition_id.
  """
  @spec queue_get_paused(partition_id :: String.t) :: {:ok, MapSet.t}
  def queue_get_paused(partition_id) do
    partition_call(partition_id, :queue_get_paused)
  end

  @doc false
  @spec partition_call(partition_id :: String.t, request :: any) :: :ok | true | false | {:ok, any} | {:error, :not_started}
  defp partition_call(partition_id, request) do
    try do
      case GenServer.call(global_name(partition_id), request) do
        :ok -> :ok
        true -> true
        false -> false
        result -> {:ok, result}
      end
    catch
      :exit, {:noproc, _} ->
        {:error, :not_started}
    end
  end

  @doc false
  def global_name(id) when is_binary(id) do
    {:global, {:app_global, id}}
  end

  ## Server side

  @save_interval 1000

  def init([partition_id]) do
    Process.flag(:trap_exit, true)
    Process.send_after(self(), :save, @save_interval)
    :ok = apply(persister_module(), :init, [partition_id])
    {:ok, load(partition_id)}
  end

  def terminate(kind, state) when kind in [:normal, :shutdown] do
    save(state)
  end

  def terminate(_, _), do: nil

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
    System.call(:queue_pause, queue: queue, partition_id: state.partition_id)
    {:reply, :ok, %{state | paused: MapSet.put(state.paused, queue), dirty: true}}
  end

  def handle_call({:queue_resume, queue}, _from, state) do
    System.call(:queue_resume, queue: queue, partition_id: state.partition_id)
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

  defp load(partition_id) do
    case apply(persister_module(), :load, [partition_id]) do
      {:ok, data} ->
        state = State.deserialize(data)
        %State{state | partition_id: partition_id}
      {:error, _} ->
        State.new(partition_id)
    end
  end

  defp save(%State{dirty: false} = state) do
    state
  end
  defp save(state) do
    apply(persister_module(), :store, [state.partition_id, State.serialize(state)])
    %State{state | dirty: false}
  end
  
  defp persister_module do
    Application.get_env(:roger, :persister) || Roger.Partition.Global.StatePersister.Stub
  end

end
