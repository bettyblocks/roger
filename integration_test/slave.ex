defmodule Roger.Integration.Slave do
  @moduledoc false

  require Logger

  defmodule WorkerCallback do
    @moduledoc false
    use Roger.Partition.Worker.Callback

    def after_run(_app, job, _, _) do
      GenServer.cast(Roger.Integration.Slave, {:job_done, job.module})
    end
  end

  use GenServer

  defmodule State do
    @moduledoc false
    defstruct master: nil, done_count: 0
  end

  def start_link(master) do
    GenServer.start_link(__MODULE__, [master]) |> IO.inspect(label: "genserver start")
  end

  def init([master]) do
    Logger.error("init #{inspect(master)} starting")
    {:ok, %State{master: master}, {:continue, :setup}}
  end

  def handle_cast({:job_done, _module}, state) do
    state = %{state | done_count: state.done_count + 1}
    {:noreply, state}
  end

  def handle_info(:done, state) do
    done(state)
    {:noreply, state}
  end

  def handle_continue(:setup, state) do
    Application.put_env(:roger, :callbacks, WorkerCallback)
    Logger.error("timeout")
    result = Application.ensure_all_started(:roger)
    Logger.error("#{inspect(result)} ensure started")
    {:ok, _} = result |> IO.inspect(label: "starting stuff")
    Logger.error("ensuring started")
    {:ok, _pid} = Roger.Partition.start("integration", default: 10) |> IO.inspect(label: "starting partition")
    Logger.error("booting complete")

    spawn(fn ->
      :timer.sleep(1000)
      log(state.master, "ready")
      IO.inspect({:ready, node()}, label: "sending message")
      send(state.master, {:ready, node()}) |> IO.inspect(label: "message")
    end)

    {:noreply, state}
  end

  defp log(master, msg) do
    send(master, {:log, node(), msg})
  end

  defp done(state) do
    send(state.master, {:done, node(), state.done_count})
  end
end
