defmodule Roger.Partition do
  @moduledoc """
  Per-node partition registry

  Roger implements multi-tenancy by dividing all its work between
  different "Partitions". Each partition is identified by a unique
  ID. Partitions consist of a list of queues, which are defined by its
  type (an atom) and a max_workers value which sets the concurrency
  level. The RabbitMQ queue name is constructed of the partition ID +
  the queue type.

  To spread out the work, partitions can be started in the cluster on
  multiple nodes. The partition's queue configuration can be different
  between nodes - i.e. some node might be able to handle more
  concurrency than others.

  Within the cluster, there is one global process
  (`Roger.Partition.Global`) which manages the partition's state. In
  it, it manages job's uniqueness, states of paused queues, et cetera.

  """

  use GenServer
  alias Roger.{Partition.Consumer, System, Partition.Global}

  require Logger

  @type queue_def :: {id :: String.t, max_workers :: non_neg_integer}

  @doc false
  def start_link do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @doc """
  Start a Roger partition

  Given a unique ID and a list of queues, starts the partition
  supervision structure. When the partition has already been
  started, this calls `reconfigure/2` instead.
  """
  @spec start(id :: String.t, queues :: [queue_def]) :: {:ok, pid}
  def start(id, queues) do
    GenServer.call(__MODULE__, {:start, id, queues})
  end

  @doc """
  Stop the given Roger partition
  """
  @spec stop(id :: String.t) :: :ok | {:error, :not_running}
  def stop(id) do
    GenServer.call(__MODULE__, {:stop, id})
  end

  @doc """
  Reconfigure the given Roger partition

  Use this function to adjust the queues for the partition. The
  queues argument is *complete*: any queues that are not mentioned,
  are stopped and messages in them will no longer be processed on this
  node.
  """
  @spec reconfigure(id :: String.t, queues :: [queue_def]) :: :ok | {:error, :not_running}
  def reconfigure(id, queues) do
    if Consumer.is_alive?(id) do
      Consumer.reconfigure(id, queues)
    else
      {:error, :not_running}
    end
  end

  defmodule State do
    @moduledoc false
    defstruct waiting: %{}, monitored: %{}
  end

  def init([]) do
    {:ok, %State{}, 0}
  end

  def handle_call({:start, id, queues}, _from, state) do
    {reply, state} = start_partition(id, queues, state)
    {:reply, reply, state}
  end

  def handle_call({:stop, partition}, _from, state) do
    {reply, state} = stop_partition(partition, state)
    {:reply, reply, state}
  end

  def handle_call(:waiting_partitions, _from, state) do
    {:reply, state.waiting, state}
  end

  def handle_info(:timeout, state) do
    Process.send_after(self(), :check, 1000)
    apps = get_predefined_apps()
    state = start_all(apps, state)
    {:noreply, state}
  end

  def handle_info(:check, state) do
    Process.send_after(self(), :check, 1000)
    if System.connected? and Enum.count(state.waiting) > 0 do
      # try to connect some partitions
      {_pids, apps} = Enum.unzip(state.waiting)
      {:noreply, start_all(apps, Map.put(state, :waiting, %{}))}
    else
      {:noreply, state}
    end
  end

  def handle_info({:DOWN, _, :process, pid, _}, state) do
    # remove from monitors, put in waiting state
    case state.monitored[pid] do
      nil ->
        {:noreply, state}
      {id, queues} ->
      {:noreply, %State{state |
                        waiting: Map.put(state.waiting, id, {id, queues}),
                        monitored: Map.delete(state.monitored, pid)}}
    end
  end

  defp start_all(partitions, state) do
    partitions
    |> Enum.reduce(state, fn({id, queues}, state) ->
      {_reply, state} = start_partition(id, queues, state)
      state
    end)
  end

  defp start_partition(id, queues, state) when is_atom(id) do
    start_partition(Atom.to_string(id), queues, state)
  end

  defp start_partition(id, queues, state) do
    if System.connected? do
      # make sure a statemanager instance is running
      Singleton.start_child(Global, [id], {:app_global, id})
      # start partition supervision tree
      pid = case Roger.PartitionSupervisor.start_child(id) do
              {:ok, pid} ->
                Logger.debug "Started Roger partition: #{id}"
                pid
              {:error, {:already_started, pid}} ->
                pid
            end
      :ok = Consumer.reconfigure(id, queues)
      _ref = Process.monitor(pid)
      {{:ok, pid}, %State{state | monitored: Map.put(state.monitored, pid, {id, queues})}}
    else
      {:waiting, %State{state | waiting: Map.put(state.waiting, id, {id, queues})}}
    end
  end

  defp stop_partition(id, state) do
    case Roger.GProc.whereis({:app_supervisor, id}) do
      pid when is_pid(pid) ->
        :ok = Roger.PartitionSupervisor.stop_child(pid)
        {:ok, %State{state | monitored: Map.delete(state.monitored, pid)}}
      :nil ->
        {{:error, :not_running}, state}
    end
  end

  defp get_predefined_apps() do
    :application.get_env(:roger, :partitions, [])
  end

end
