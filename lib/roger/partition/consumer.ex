defmodule Roger.Partition.Consumer do
  @moduledoc """

  Job consumer process.

  This process is responsible for maintaining subscriptions to the
  partition's channels and receives jobs. For each job, it spawns
  off a worker process.

  """

  require Logger
  alias Roger.{Queue, GProc, Partition.WorkerSupervisor, Partition.Global}

  use GenServer

  def start_link(partition_id) do
    GenServer.start_link(__MODULE__, [partition_id], name: GProc.via(name(partition_id)))
  end

  def is_alive?(partition_id) do
    GProc.is_alive(name(partition_id))
  end

  def get_queues(partition_id) do
    GenServer.call(GProc.via(name(partition_id)), :get_queues)
  end

  def reconfigure(partition_id, queues) do
    GenServer.call(GProc.via(name(partition_id)), {:reconfigure, queues})
  end

  def pause(partition_id, queue) do
    if is_alive?(partition_id) do
      GenServer.call(GProc.via(name(partition_id)), {:pause, queue})
    end
  end

  @doc """
  Pauses all running queues on current consumer
  """
  @spec pause_all(String.t()) :: :ok | nil
  def pause_all(partition_id) do
    if is_alive?(partition_id) do
      GenServer.call(GProc.via(name(partition_id)), {:pause_all})
    end
  end

  def resume(partition_id, queue) do
    if is_alive?(partition_id) do
      GenServer.call(GProc.via(name(partition_id)), {:resume, queue})
    end
  end

  defp name(id) when is_binary(id) do
    {:app_job_consumer, id}
  end

  ## Server interface

  defmodule State do
    @moduledoc false
    defstruct partition_id: nil, channel: nil, queues: [], paused: MapSet.new(), closing: %{}, pausing: %{}

    def queue_pause(state, queue) do
      %{state | paused: MapSet.put(state.paused, queue)}
    end
  end

  def init([partition_id]) do
    {:ok, paused} = Global.queue_get_paused(partition_id)
    {:ok, %State{partition_id: partition_id, paused: paused}}
  end

  def handle_call(:get_queues, _from, state) do
    # strip channel from the queues
    # queues = state.queues |> Enum.map(fn(q) -> %{q | channel: nil} end)
    {:ok, channel} = Roger.AMQPClient.open_channel()

    reply =
      state.queues
      |> Enum.map(fn q ->
        paused = MapSet.member?(state.paused, q.type)
        queue_name = Queue.make_name(state.partition_id, q.type)
        {:ok, stats} = AMQP.Queue.declare(channel, queue_name, durable: true)

        {q.type,
         %{
           max_workers: q.max_workers,
           paused: paused,
           message_count: stats.message_count,
           consumer_count: stats.consumer_count
         }}
      end)
      |> Enum.into(%{})

    AMQP.Channel.close(channel)
    {:reply, reply, state}
  end

  def handle_call({:reconfigure, queues}, _from, state) do
    {:reply, :ok, do_reconfigure(state, queues)}
  end

  def handle_call({:pause, queue}, _from, state) do
    state = State.queue_pause(state, queue)
    {:reply, :ok, state}
  end

  def handle_call({:pause_all}, _from, state) do
    state =
      Enum.reduce(state.queues, state, fn queue, state ->
        State.queue_pause(state, queue.type)
      end)

    {:reply, :ok, state}
  end

  def handle_call({:resume, queue}, _from, state) do
    state = resume_queue(queue, state)
    {:reply, :ok, state}
  end

  def handle_info({:basic_consume_ok, %{consumer_tag: consumer_tag}}, state) do
    # Confirmation sent by the broker after registering this process as a consumer
    queues =
      List.foldr(state.queues, [], fn q, acc ->
        queue = %{q | confirmed: q.confirmed || q.consumer_tag == consumer_tag}
        [queue | acc]
      end)

    {:noreply, Map.put(state, :queues, queues)}
  end

  def handle_info({:basic_cancel, %{consumer_tag: _consumer_tag}}, state) do
    # FIXME handle a cancel? (server-initiated close, e.g. when a queue gets deleted)
    {:noreply, state}
  end

  def handle_info({:basic_cancel_ok, %{consumer_tag: consumer_tag}}, state) do
    if Map.has_key?(state.closing, consumer_tag) do
      :ok = AMQP.Channel.close(state.closing[consumer_tag])
      {:noreply, %{state | closing: Map.delete(state.closing, consumer_tag)}}
    else
      if Map.has_key?(state.pausing, consumer_tag) do
        {:noreply, %{state | pausing: Map.delete(state.pausing, consumer_tag)}}
      else
        {:noreply, state}
      end
    end
  end

  def handle_info({:basic_deliver, payload, meta}, state) do
    queue = find_queue_by_tag(meta.consumer_tag, state)

    if queue != nil do
      if !MapSet.member?(state.paused, queue.type) do
        # Start handling the message
        {:ok, _pid} = WorkerSupervisor.start_child(state.partition_id, queue.channel, payload, meta)
        {:noreply, state}
      else
        # We got a message but for a queue that was paused. Stop consuming the queue.
        state = pause_queue(queue, state)
        AMQP.Basic.nack(queue.channel, meta.delivery_tag)
        {:noreply, state}
      end
    else
      if Map.has_key?(state.pausing, meta.consumer_tag) do
        # got a message for a channel that is in the process of pausing
        AMQP.Basic.nack(state.pausing[meta.consumer_tag], meta.delivery_tag)
      end

      {:noreply, state}
    end
  end

  def handle_info({:DOWN, _ref, :process, _pid, _}, state) do
    # Shut down the partition when a channel closes unexpectedly
    Logger.debug("Terminating partition #{state.partition_id} due to connection error")
    :ok = Roger.Partition.ContainingSupervisor.stop(state.partition_id)
    {:stop, :normal, state}
  end

  ## Internal functions

  defp do_reconfigure(state, new_queues) do
    existing_queue_types = for(q <- state.queues, do: q.type) |> Enum.into(MapSet.new())
    new_queues = for {type, max_workers} <- new_queues, do: Queue.define(type, max_workers)
    new_queue_types = for(q <- new_queues, do: q.type) |> Enum.into(MapSet.new())

    pick = fn types, queues ->
      queues |> Enum.filter(fn q -> MapSet.member?(types, q.type) end)
    end

    # close channels of queues that are not in new_queues
    closing =
      MapSet.difference(existing_queue_types, new_queue_types)
      |> pick.(state.queues)
      |> Enum.map(fn q ->
        if q.consumer_tag != nil do
          {:ok, _} = AMQP.Basic.cancel(q.channel, q.consumer_tag)
        end

        {q.consumer_tag, q.channel}
      end)
      |> Enum.into(%{})

    # reconfigure channels that have changed
    {existing_queues, pausing} =
      MapSet.intersection(new_queue_types, existing_queue_types)
      |> pick.(state.queues)
      |> Enum.reduce({[], state.pausing}, fn q, {existing, pausing} ->
        new_q = Enum.find(new_queues, &(&1.type == q.type))
        # currently, max_workers is the only channel property that can
        # change. When it changes to 0 we need to stop consuming.
        cond do
          new_q.max_workers == q.max_workers ->
            # nothing changed
            {[q | existing], pausing}

          new_q.max_workers > 0 ->
            # new max_workers
            q = %{q | max_workers: new_q.max_workers}

            if q.consumer_tag != nil do
              {:ok, _} = AMQP.Basic.cancel(q.channel, q.consumer_tag)
            end

            :ok = AMQP.Basic.qos(q.channel, prefetch_count: q.max_workers)
            {[consume(q, state) | existing], pausing}

          new_q.max_workers == 0 ->
            # max_workers changed to 0
            {:ok, _} = AMQP.Basic.cancel(q.channel, q.consumer_tag)
            {existing, Map.put(pausing, q.consumer_tag, q.channel)}
        end
      end)

    # open channels of queues that are in new queues but not in partition queues
    new_queues =
      MapSet.difference(new_queue_types, existing_queue_types)
      |> pick.(new_queues)
      |> Enum.map(fn q ->
        {:ok, q} = Queue.setup_channel(q)
        Process.monitor(q.channel.pid)

        if !MapSet.member?(state.paused, q.type) and q.max_workers > 0 do
          consume(q, state)
        else
          q
        end
      end)

    queues = (existing_queues ++ new_queues) |> Enum.sort(&(&1.type < &2.type))

    %State{state | queues: queues, closing: closing, pausing: pausing}
  end

  defp find_queue_by_tag(consumer_tag, state) do
    state.queues |> Enum.find(&(&1.consumer_tag == consumer_tag))
  end

  defp find_queue_by_type(type, state) do
    state.queues |> Enum.find(&(&1.type == type))
  end

  defp pause_queue(queue, state) do
    # We got a message for a paused queue. nack the message and stop consuming the queue.
    if queue.consumer_tag != nil do
      {:ok, _} = AMQP.Basic.cancel(queue.channel, queue.consumer_tag)

      queues =
        Enum.map(state.queues, fn q ->
          if q.consumer_tag == queue.consumer_tag do
            %{q | consumer_tag: nil}
          else
            q
          end
        end)

      %{state | queues: queues, pausing: Map.put(state.pausing, queue.consumer_tag, queue.channel)}
    else
      state
    end
  end

  defp resume_queue(type, state) do
    if MapSet.member?(state.paused, type) do
      queue = find_queue_by_type(type, state)

      queues =
        Enum.map(state.queues, fn q ->
          if queue != nil && q.type == queue.type do
            consume(q, state)
          else
            q
          end
        end)

      %{state | paused: MapSet.delete(state.paused, type), queues: queues}
    else
      state
    end
  end

  defp consume(queue, state) do
    queue_name = Queue.make_name(state.partition_id, queue.type)
    # FIXME: do something with stats?
    {:ok, _stats} = AMQP.Queue.declare(queue.channel, queue_name, durable: true)
    {:ok, consumer_tag} = AMQP.Basic.consume(queue.channel, queue_name)

    %Queue{
      queue
      | consumer_tag: consumer_tag,
        confirmed: false
    }
  end
end
