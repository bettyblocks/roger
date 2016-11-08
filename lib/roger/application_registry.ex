defmodule Roger.ApplicationRegistry do
  @moduledoc """
  Per-node registry of all applications that are started.
  """

  use GenServer
  alias Roger.{Application, Application.Consumer, System, Application.Global}

  require Logger

  def start_link do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  def start(%Application{} = application) do
    GenServer.call(__MODULE__, {:start, application})
  end

  def stop(%Application{} = application) do
    GenServer.call(__MODULE__, {:stop, application})
  end

  def running_applications do
    for {:app_supervisor, id} <- Roger.GProc.find_names({:app_supervisor, :_}) do
      %Application{id: id, queues: Consumer.get_queues(id)}
    end
  end

  def waiting_applications do
    GenServer.call(__MODULE__, :waiting_applications)
  end

  defmodule State do
    @moduledoc false
    defstruct waiting: %{}, monitored: %{}
  end

  def init([]) do
    {:ok, %State{}, 0}
  end

  def handle_call({:start, application}, _from, state) do
    {reply, state} = start_application(application, state)
    {:reply, reply, state}
  end

  def handle_call({:stop, application}, _from, state) do
    {reply, state} = stop_application(application, state)
    {:reply, reply, state}
  end

  def handle_call(:waiting_applications, _from, state) do
    {:reply, Map.values(state.waiting), state}
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
    app = state.monitored[pid]
    if app != nil do
      {:noreply, %State{state |
                        waiting: Map.put(state.waiting, app.id, app),
                        monitored: Map.delete(state.monitored, pid)}}
    else
      {:noreply, state}
    end
  end

  def start_all(applications, state) do
    applications
    |> Enum.reduce(state, fn(application, state) ->
      {_reply, state} = start_application(application, state)
      state
    end)
  end

  defp start_application(application, state) do
    if System.connected? do
      # make sure a statemanager instance is running
      Singleton.start_child(Global, [application], {:app_global, application.id})
      # start application supervision tree
      pid = case Roger.ApplicationSupervisor.start_child(application) do
              {:ok, pid} ->
                Logger.debug "Started Roger application: #{application.id}"
                pid
              {:error, {:already_started, pid}} ->
                :ok = Consumer.reconfigure(application)
                pid
            end
      _ref = Process.monitor(pid)
      {{:ok, pid}, %State{state | monitored: Map.put(state.monitored, pid, application)}}
    else
      {:waiting, %State{state | waiting: Map.put(state.waiting, application.id, application)}}
    end
  end

  defp stop_application(application, state) do
    case Roger.GProc.whereis({:app_supervisor, application.id}) do
      pid when is_pid(pid) ->
        :ok = Roger.ApplicationSupervisor.stop_child(pid)
        {:ok, %State{state | monitored: Map.delete(state.monitored, pid)}}
      :nil ->
        {{:error, :not_running}, state}
    end
  end

  defp get_predefined_apps() do
    :application.get_env(:roger, :applications, [])
    |> Enum.map(fn({id, queues}) ->
      queues = (for q <- queues, do: Roger.Queue.define(q))
      %Application{id: "#{id}", queues: queues}
    end)
  end

end
