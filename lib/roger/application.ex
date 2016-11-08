defmodule Roger.Application do
  @moduledoc """
  Per-node registry of all applications that are started.

  Roger implements multi-tenancy by dividing all its work between
  different Applications. (this name might be confusing - an OTP
  application is something different!)

  Each application is identified by a unique ID. Applications have a
  list of queues, which are defined by its type (an atom) and a
  max_workers value which sets the concurrency level.

  """

  use GenServer
  alias Roger.{Application.Consumer, System, Application.Global}

  require Logger

  def start_link do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  def start(id, queues) do
    GenServer.call(__MODULE__, {:start, id, queues})
  end

  def stop(id) do
    GenServer.call(__MODULE__, {:stop, id})
  end

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
    {reply, state} = start_application(id, queues, state)
    {:reply, reply, state}
  end

  def handle_call({:stop, application}, _from, state) do
    {reply, state} = stop_application(application, state)
    {:reply, reply, state}
  end

  def handle_call(:waiting_applications, _from, state) do
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
      # try to connect some applications
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

  def start_all(applications, state) do
    applications
    |> Enum.reduce(state, fn({id, queues}, state) ->
      {_reply, state} = start_application(id, queues, state)
      state
    end)
  end

  defp start_application(id, queues, state) when is_atom(id) do
    start_application(Atom.to_string(id), queues, state)
  end

  defp start_application(id, queues, state) do
    if System.connected? do
      # make sure a statemanager instance is running
      Singleton.start_child(Global, [id], {:app_global, id})
      # start application supervision tree
      pid = case Roger.ApplicationSupervisor.start_child(id) do
              {:ok, pid} ->
                Logger.debug "Started Roger application: #{id}"
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

  defp stop_application(id, state) do
    case Roger.GProc.whereis({:app_supervisor, id}) do
      pid when is_pid(pid) ->
        :ok = Roger.ApplicationSupervisor.stop_child(pid)
        {:ok, %State{state | monitored: Map.delete(state.monitored, pid)}}
      :nil ->
        {{:error, :not_running}, state}
    end
  end

  defp get_predefined_apps() do
    :application.get_env(:roger, :applications, [])
  end

end
