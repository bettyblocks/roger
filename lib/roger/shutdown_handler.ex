defmodule Roger.ShutdownHandler do
  @moduledoc """
  This module handles correctly shutting down the workers.
  By first stop consuming new jobs and then wait for certain time for workers to finish.
  """

  use GenServer, restart: :transient, shutdown: 4_500_000

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
    System.set_inactive()

    timer_ref = :erlang.start
    IO.inspect "handle shutdown"
    :timer.sleep 10_000
    Roger.AMQPClient.close()
    IO.inspect "completed handling"
  end

  defp stop_consumers() do

  end

  defp await_workers() do

  end

end
