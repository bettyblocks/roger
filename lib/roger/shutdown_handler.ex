defmodule Roger.ShutdownHandler do
  @moduledoc """
  This module handles correctly shutting down the workers.
  By first stop consuming new jobs and then wait for certain time for workers to finish.
  """

  @shutdown_overflow 10_000
  @shutdown_timeout Application.get_env(:roger, :shutdown_timeout, 15_000) + @shutdown_overflow
  use GenServer, restart: :transient, shutdown: @shutdown_timeout

  require Logger

  alias Roger.System

  def start_link([]) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  def init([]) do
    Process.flag(:trap_exit, true)
    {:ok, %{}}
  end

  def terminate({:shutdown, _reason}, _), do: handle_shutdown()
  def terminate(:shutdown, _), do: handle_shutdown()
  def terminate(:normal, _), do: handle_shutdown()
  def terminate(_, _), do: nil

  defp handle_shutdown() do
    Logger.info("Gracefully shutting down Roger.")

    with :ok = System.set_inactive(),
         :ok = System.unsubscribe_all() do
      Logger.info("Stopped Roger from accepting new jobs")
      timer = :erlang.start_timer(@shutdown_timeout - @shutdown_overflow, self(), :end_of_grace_period)

      Roger.NodeInfo.running_worker_pids()
      |> Enum.map(&Process.monitor(&1))
      |> Enum.into(MapSet.new())
      |> await_workers(timer)

      Enum.each(Roger.NodeInfo.running_partitions(), fn {key, _} ->
        Roger.Partition.stop(key)
      end)

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
        Logger.warn("Terminated #{MapSet.size(worker_pids)} jobs because it took longer then termination timeout.")
        :ok
    end
  end
end
