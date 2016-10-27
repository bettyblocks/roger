defmodule Roger.AMQPClient do
  require Logger

  use AMQP

  use GenServer

  def start_link(config) do
    GenServer.start_link(__MODULE__, [config], name: __MODULE__)
  end

  def open_channel() do
    GenServer.call(__MODULE__, :open_channel)
  end

  def publish(exchange, routing_key, payload, opts \\ []) do
    GenServer.call(__MODULE__, {:publish, exchange, routing_key, payload, opts})
  end

  ## Server interface

  defmodule State do
    defstruct config: nil, connection: nil, client_channel: nil
  end

  def init([config]) do
    {:ok, %State{config: config}, 0}
  end

  def handle_call({:publish, exchange, routing_key, payload, opts}, _from, state) do
    reply = Basic.publish(state.client_channel, exchange, routing_key, payload, opts)
    {:reply, reply, state}
  end

  def handle_call(:open_channel, _from, state) do
    # FIXME what if we're not connected?
    # FIXME limit the nr of channels?
    reply = {:ok, _} = Channel.open(state.connection)
    {:reply, reply, state}
  end

  def handle_info(:timeout, state) do
    {:noreply, reconnect(state)}
  end

  def handle_info(msg, state) do
    IO.puts "msg: #{inspect msg}"

    {:noreply, state}
  end

  defp reconnect(state) do
    case Connection.open(state.config) do
      {:ok, connection} ->
        {:ok, client_channel} = Channel.open(connection)
        %State{state | connection: connection, client_channel: client_channel}
      {:error, _} = e ->
        Logger.warn "AMQP error: #{inspect e}"
        Process.send_after(self(), :timeout, 5000) # reconnect
        state
    end
  end

end
