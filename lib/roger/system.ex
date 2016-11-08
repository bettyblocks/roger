defmodule Roger.System do
  @moduledoc """

  Listener for system-wide events.

  On the AMQP side, the systemchannel declares a fanout exchange
  called 'system' and adds a private queue to it, which it consumes.

  """

  use GenServer
  use AMQP

  @system_exchange "system"
  @command_content_type "roger/system-command"
  @reply_content_type "roger/system-reply"

  require Logger
  alias Roger.System.Command

  @doc false
  def start_link do
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

  @doc """
  Return whether the node is connected to the AMQP broker
  """
  def connected? do
    GenServer.call(__MODULE__, :is_connected)
  end

  ###

  defmodule Reply do
    @moduledoc false
    defstruct from: nil, replies: [], waiting: nil
    def new(from, nodes) do
      %__MODULE__{from: from, waiting: nodes}
    end
    def done?(%__MODULE__{waiting: []}), do: true
    def done?(%__MODULE__{}), do: false

    def add_reply(struct, node, reply) do
      %{struct | replies: [{node, reply} | struct.replies],
        waiting: struct.waiting -- [node]}
    end
  end

  defmodule State do
    @moduledoc false
    defstruct channel: nil, reply_queue: nil, replies: %{}
    def add_waiting_reply(state, id, from, nodes) do
      %{state | replies: Map.put(state.replies, id, Reply.new(from, nodes))}
    end

    def check_node_reply(state, id, node, reply) do
      if state.replies[id] != nil do
        reply = Reply.add_reply(state.replies[id], node, reply)
        if Reply.done?(reply) do
          GenServer.reply(reply.from, {:ok, reply.replies})
          %{state | replies: Map.delete(state.replies, id)}
        else
          # not done yet
          %{state | replies: Map.put(state.replies, id, reply)}
        end
      else
        Logger.error "#{node} Unknown reply to #{id}"
        state
      end
    end
  end


  def init([]) do
    {:ok, %State{}, 0}
  end

  def handle_call(:is_connected, _from, state) do
    {:reply, state.channel != nil, state}
  end

  def handle_call(_, _, %State{channel: nil} = state) do
    {:reply, {:error, :disconnected}, state}
  end

  # Send the command to all nodes; don't wait for response
  def handle_call({:cast, command}, _from, state) do
    payload = Command.encode(command)
    opts = [
      content_type: @command_content_type]
    :ok = Basic.publish(state.channel, @system_exchange, "", payload, opts)
    {:reply, :ok, state}
  end

  # Send the command to all nodes; record that we're waiting for a reply
  def handle_call({:call, command}, from, state) do
    payload = Command.encode(command)
    id = generate_id()
    opts = [
      content_type: @command_content_type,
      correlation_id: id,
      reply_to: state.reply_queue]
    :ok = Basic.publish(state.channel, @system_exchange, "", payload, opts)
    nodes = [node() | :erlang.nodes()]
    {:noreply, state |> State.add_waiting_reply(id, from, nodes)}
  end

  def handle_info({:basic_consume_ok, _meta}, state) do
    {:noreply, state}
  end

  def handle_info({:basic_deliver, payload, meta = %{content_type: @command_content_type}}, state) do
    command = Command.decode(payload)
    reply = try do
              dispatch_command(command)
            catch
              e ->
                Logger.warn "#{inspect e}"
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

  def handle_info(:timeout, state) do
    case Roger.AMQPClient.open_channel do
      {:ok, channel} ->

        # Fanout / pubsub setup
        :ok = Exchange.declare(channel, @system_exchange, :fanout)
        {:ok, info} = Queue.declare(channel, "", exclusive: true)
        Queue.bind(channel, info.queue, @system_exchange)
        {:ok, _} = AMQP.Basic.consume(channel, info.queue)

        # reply queue
        {:ok, info} = Queue.declare(channel, "", exclusive: true)
        {:ok, _} = AMQP.Basic.consume(channel, info.queue)

        {:noreply, %State{state | channel: channel, reply_queue: info.queue}}

      {:error, :disconnected} ->
        Process.send_after(self(), :timeout, 1000) # try again if the AMQP client is back up
        {:noreply, %State{state | channel: nil, reply_queue: nil}}
    end
  end

  defp dispatch_command({:ping, _args}) do
    :pong
  end

  defp dispatch_command({:cancel, [job_id: job_id]}) do
    # Cancel any running jobs
    worker_name = Roger.Application.Worker.name(job_id)
    for {pid, _value} <- Roger.GProc.find_properties(worker_name) do
      Process.exit(pid, :exit)
    end
    :ok
  end

  defp dispatch_command({:queue_pause, [queue: queue, app_id: app_id]}) do
    Roger.Application.Consumer.pause(app_id, queue)
  end

  defp dispatch_command({:queue_resume, [queue: queue, app_id: app_id]}) do
    Roger.Application.Consumer.resume(app_id, queue)
  end

  defp dispatch_command({{:apply, mod, fun}, args}) do
    Kernel.apply(mod, fun, args)
  end

  defp dispatch_command({command, args}) do
    Logger.warn "Received unknown command: #{inspect command} #{inspect args}"
    {:error, :unknown_command}
  end

  defp generate_id do
    :crypto.rand_bytes(10) |> Base.hex_encode32(case: :lower)
  end

end
