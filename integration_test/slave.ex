defmodule Roger.Integration.Slave do
  @moduledoc false

  defmodule WorkerCallback do
    @moduledoc false
    use Roger.Application.Worker.Callback

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
    GenServer.start_link(__MODULE__, [master], name: __MODULE__)
  end

  def init([master]) do
    log(master, "Initializing")
    {:ok, %State{master: master}, 0}
  end

  def handle_cast({:job_done, _module}, state) do
    #log(state.master, "Job done: #{module}")
    state = %{state | done_count: state.done_count + 1}
    {:noreply, state}
  end

  def handle_info(:done, state) do
    done(state)
    {:noreply, state}
  end


  def handle_info(:timeout, state) do
    {:ok, _} = Application.ensure_all_started(:roger)
    {:ok, _pid} = Roger.Application.start("integration", [default: 10])

    Elixir.Application.put_env(:roger, :callbacks, worker: WorkerCallback)

    spawn(fn ->
      :timer.sleep 1000
      log(state.master, "ready")
      send(state.master, {:ready, node()})
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
