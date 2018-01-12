defmodule Roger.ShutdownHandler do
  @moduledoc """
  This module handles correctly shutting down the workers.
  By first stop consuming new jobs and then wait for certain time for workers to finish.
  """

  @shutdown_timeout 4_500_000
  use GenServer, restart: :transient, shutdown: @shutdown_timeout

  require Logger

  alias Roger.System

  def start_link([]) do
    IO.puts " start link"
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  def init([]) do
    IO.puts "starting shutdown handler"
    Process.flag(:trap_exit, true)
    {:ok, %{}}
  end

  def terminate({:shutdown, _reason}, state), do: handle_shutdown(state)
  def terminate(:shutdown, state), do: handle_shutdown(state)
  def terminate(:normal, state), do: handle_shutdown(state)
  def terminate(_, _), do: nil

  defp handle_shutdown(state) do
    Logger.info("Gracefully shutting down Roger.")
    with :ok = System.set_inactive(),
         :ok = System.unsubscribe_all() do
      Logger.info("Stopped Roger from accepting new jobs")
      timer = :erlang.start_timer(@shutdown_timeout - 100_000, self(), :end_of_grace_period)

      Roger.NodeInfo.running_worker_pids()
      |> Enum.map(&Process.monitor(&1))
      |> Enum.into(MapSet.new())
      |> await_workers(timer)
      Roger.AMQPClient.close()
      Logger.info("Finished shutting down roger.")
    end
  end

  defp await_workers(worker_pids, _) when worker_pids == %MapSet{} do
    :ok
  end

  defp await_workers(worker_pids, timer) do
    Logger.info("Waiting for #{MapSet.size(worker_pids)} jobs to finish.")
    receive do
      {:DOWN, downed_pid, _, _, _} ->
        worker_pids
        |> MapSet.delete(downed_pid)
        |> await_workers(timer)
      {:timeout, ^timer, :end_of_grace_period} ->
        :ok
    end
  end

end
