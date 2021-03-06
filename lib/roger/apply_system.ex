defmodule Roger.ApplySystem do
  @moduledoc """

  Listener for system-wide events.

  On the AMQP side, the systemchannel declares a fanout exchange
  called 'system' and adds a private queue to it, which it consumes.

  This is the apply part of system mostly just to handle NodeInfo requests.
  Split is done to reduce load of genserver.

  """

  use GenServer
  use AMQP

  @system_exchange "apply-system"
  @command_content_type "roger/system-command"
  @reply_content_type "roger/system-reply"

  require Logger
  alias Roger.System.Command
  alias Roger.System.State

  @doc false
  def start_link(_) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @doc """
  Execute a given command on all nodes, and wait for all nodes to return their values
  """
  def call(command, args \\ nil) do
    GenServer.call(__MODULE__, {:call, Command.new(command, args)})
  end

  @doc """
  Execute a given command on all nodes, does not wait for their completion.
  """
  def cast(command, args \\ nil) when is_atom(command) do
    GenServer.call(__MODULE__, {:cast, Command.new(command, args)})
  end

  def init([]) do
    Process.flag(:trap_exit, true)
    {:ok, %State{}, 0}
  end

  def handle_call(_, _, %State{channel: nil} = state) do
    {:reply, {:error, :disconnected}, state}
  end

  # Send the command to all nodes; don't wait for response
  def handle_call({:cast, command}, _from, state) do
    payload = Command.encode(command)

    opts = [
      content_type: @command_content_type
    ]

    :ok = Basic.publish(state.channel, system_exchange_name(), "", payload, opts)
    {:reply, :ok, state}
  end

  # Send the command to all nodes; record that we're waiting for a reply
  def handle_call({:call, command}, from, state) do
    payload = Command.encode(command)
    id = generate_id()

    opts = [
      content_type: @command_content_type,
      correlation_id: id,
      reply_to: state.reply_queue
    ]

    :ok = Basic.publish(state.channel, system_exchange_name(), "", payload, opts)
    filtered_nodes = Enum.filter(:erlang.nodes(), &(!String.contains?(Atom.to_string(&1), "_maint_")))
    nodes = [node() | filtered_nodes]
    {:noreply, state |> State.add_waiting_reply(id, from, nodes)}
  end

  def handle_info({:basic_consume_ok, _meta}, state) do
    {:noreply, state}
  end

  def handle_info({:basic_deliver, payload, meta = %{content_type: @command_content_type}}, state) do
    command = Command.decode(payload)

    reply =
      try do
        dispatch_command(command, state)
      catch
        e ->
          Logger.warn("#{inspect(e)}")
      end

    payload = :erlang.term_to_binary({node(), reply})

    if meta.correlation_id != :undefined do
      opts = [content_type: @reply_content_type, correlation_id: meta.correlation_id]
      :ok = Basic.publish(state.channel, "", meta.reply_to, payload, opts)
    end

    {:noreply, state}
  end

  def handle_info({:basic_deliver, payload, meta = %{content_type: @reply_content_type}}, state) do
    {from_node, reply} = :erlang.binary_to_term(payload)
    {:noreply, state |> State.check_node_reply(meta.correlation_id, from_node, reply)}
  end

  def handle_info({:DOWN, _ref, :process, _pid, _}, state) do
    # try again if the AMQP client is back up
    close_channel(state)
    Process.send_after(self(), :timeout, 1000)
    {:noreply, %State{state | channel: nil}}
  end

  def handle_info({:EXIT, _, reason}, state) do
    close_channel(state)
    {:stop, reason, %State{state | channel: nil}}
  end

  def handle_info(:timeout, state) do
    connection_name = Application.get_env(:roger, :connection_name)
    # If channel still open make sure it's closed
    close_channel(state)

    with {:ok, amqp_conn} <- AMQP.Application.get_connection(connection_name),
         {:ok, channel} <- AMQP.Channel.open(amqp_conn) do
      Process.monitor(channel.pid)
      Process.link(channel.pid)
      # Fanout / pubsub setup
      :ok = Exchange.declare(channel, system_exchange_name(), :fanout)
      {:ok, info} = Queue.declare(channel, node_name(), exclusive: true)
      Queue.bind(channel, info.queue, system_exchange_name())
      {:ok, _} = AMQP.Basic.consume(channel, info.queue, nil, no_ack: true)

      # reply queue
      {:ok, info} = Queue.declare(channel, reply_node_name(), exclusive: true)

      {:ok, _} = AMQP.Basic.consume(channel, info.queue, nil, no_ack: true)

      {:noreply, %State{state | channel: channel, reply_queue: info.queue}}
    else
      {:error, error} when error in [:not_connected, :closing] ->
        # try again if the AMQP client is back up
        Process.send_after(self(), :timeout, 1000)
        {:noreply, %State{state | channel: nil, reply_queue: nil}}
    end
  end

  def terminate(_reason, state), do: close_channel(state)

  defp close_channel(%{channel: %{pid: pid} = channel}) do
    if Process.alive?(pid) do
      AMQP.Channel.close(channel)
    end
  end

  defp close_channel(_), do: nil

  defp node_name do
    "apply-" <> to_string(Node.self())
  end

  defp reply_node_name do
    node_name() <> "-reply"
  end

  defp dispatch_command({{:apply, mod, fun}, args}, _state) do
    Kernel.apply(mod, fun, args)
  end

  defp dispatch_command({command, args}, _state) do
    Logger.warn("Received unknown command: #{inspect(command)} #{inspect(args)}")
    {:error, :unknown_command}
  end

  defp generate_id do
    :crypto.strong_rand_bytes(10) |> Base.hex_encode32(case: :lower)
  end

  defp system_exchange_name do
    prefix =
      if p = Application.get_env(:roger, :system_exchange_prefix) do
        "#{p}-"
      else
        ""
      end

    prefix <> @system_exchange
  end
end
