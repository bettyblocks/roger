defmodule Roger.AMQPClient do
  @moduledoc """

  Worker process which holds the AMQP connection.
  """

  require Logger

  use AMQP

  use GenServer

  @doc """
  Starts the client and connects to RabbitMQ.
  """
  def start_link(config) do
    GenServer.start_link(__MODULE__, [config], name: __MODULE__)
  end

  @doc """
  Open a channel to RabbitMQ and return it. This also links the calling process to the connection.
  """
  def open_channel() do
    case GenServer.call(__MODULE__, :open_channel) do
      {:ok, channel} ->
        if !test?, do: Process.link(channel.pid)
        {:ok, channel}
      {:error, _} = e ->
        e
    end
  end

  @env Mix.env
  defp test?, do: @env == :test

  @doc """
  Publishes a message to RabbitMQ.

  The AMQP client automatically opens a single channel dedicated for
  sending messages.
  """
  def publish(exchange, routing_key, payload, opts \\ []) do
    GenServer.call(__MODULE__, {:publish, exchange, routing_key, payload, opts})
  end

  @doc """
  Closes the AMQP connection.

  This will cause all running Roger applications to shut down. They
  will be retried until the connection comes up again.
  """
  def close do
    GenServer.call(__MODULE__, :close)
  end

  ## Server interface

  defmodule State do
    @moduledoc false
    defstruct config: nil, connection: nil, client_channel: nil
  end

  def init([config]) do
    {:ok, %State{config: config}, 0}
  end

  def handle_call(_, _from, %{connection: nil} = state) do
    {:reply, {:error, :disconnected}, state}
  end

  def handle_call({:publish, exchange, routing_key, payload, opts}, _from, state) do
    reply = amqp_response(Basic.publish(state.client_channel, exchange, routing_key, payload, opts))
    {:reply, reply, state}
  end

  def handle_call(:open_channel, _from, state) do
    reply = amqp_response(Channel.open(state.connection))
    {:reply, reply, state}
  end

  def handle_call(:get_connection_pid, _from, state) do
    {:reply, state.connection.pid, state}
  end

  def handle_call(:close, _from, state) do
    reply = Connection.close(state.connection)
    {:reply, reply, state}
  end

  # Handles when the AMQP connection goes down
  def handle_info({:DOWN, _, :process, pid, _}, %{connection: %{pid: pid}} = state) do
    Logger.debug "AMQP connection lost"
    Process.send_after(self(), :timeout, 1000) # reconnect
    {:noreply, %{state | connection: nil, client_channel: nil}}
  end

  def handle_info(:timeout, state) do
    {:noreply, reconnect(state)}
  end

  defp reconnect(state) do
    case Connection.open(state.config) do
      {:ok, connection} ->
        {:ok, client_channel} = Channel.open(connection)
        Logger.debug "AMQP client connected."

        state=%State{state | connection: connection, client_channel: client_channel}
        Process.monitor(connection.pid)
        state
      {:error, _} = e ->
        Logger.debug "AMQP error: #{inspect e}"
        Process.send_after(self(), :timeout, 5000) # reconnect
        %State{state | connection: nil, client_channel: nil}
    end
  end

  defp amqp_response(:ok), do: :ok
  defp amqp_response({:ok, _} = r), do: r
  defp amqp_response(:closing), do: {:error, :disconnected}
  defp amqp_response({:error, _} = e), do: e

end
