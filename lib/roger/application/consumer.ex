defmodule Roger.Application.Consumer do
  @moduledoc """

  Job consumer process.

  This process is responsible for maintaining subscriptions to the
  application's channels and receives jobs. For each job, it spawns
  off a worker process.

  """

  require Logger
  alias Roger.{Queue, GProc, Application,
               Application.WorkerSupervisor,
               Application.StateManager}

  use GenServer

  def start_link(%Application{} = application) do
    GenServer.start_link(__MODULE__, [application], name: GProc.via(name(application)))
  end

  def is_alive?(application) do
    GProc.is_alive(name(application))
  end

  def get_queues(application) do
    GenServer.call(GProc.via(name(application)), :get_queues)
  end

  def reconfigure(application) do
    GenServer.call(GProc.via(name(application)), {:reconfigure, application})
  end

  def pause(application, queue) do
    GenServer.call(GProc.via(name(application)), {:pause, queue})
  end

  def resume(application, queue) do
    GenServer.call(GProc.via(name(application)), {:resume, queue})
  end

  defp name(%Application{id: id}) do
    name(id)
  end
  defp name(id) when is_binary(id) do
    {:app_job_consumer, id}
  end


  ## Server interface

  defmodule State do
    defstruct application: nil, channel: nil, queues: [], paused: MapSet.new, closing: %{}
  end

  def init([application]) do
    paused = StateManager.queue_get_paused(application)
    {:ok, %State{application: application, paused: paused}, 0}
  end

  def handle_call(:get_queues, _from, state) do
    # strip channel from the queues
    queues = state.queues |> Enum.map(fn(q) -> %{q | channel: nil} end)
    {:reply, queues, state}
  end

  def handle_call({:reconfigure, application}, _from, state) do
    {reply, state} =
      case reconfigure_valid?(application, state) do
        :ok -> {:ok, do_reconfigure(state, application)}
        e -> {e, state}
      end
    {:reply, reply, state}
  end

  def handle_call({:pause, queue}, _from, state) do
    state = %{state | paused: MapSet.put(state.paused, queue)}
    {:reply, :ok, state}
  end

  def handle_call({:resume, queue}, _from, state) do
    state = resume_queue(queue, state)
    {:reply, :ok, state}
  end

  def handle_info({:basic_consume_ok, %{consumer_tag: consumer_tag}}, state) do
    # Confirmation sent by the broker after registering this process as a consumer
    queues = List.foldr(state.queues, [], fn(q, acc) ->
      queue = %{q | confirmed: q.confirmed || q.consumer_tag == consumer_tag}
      [queue | acc]
    end)
    {:noreply, Map.put(state, :queues, queues)}
  end

  def handle_info({:basic_cancel_ok, %{consumer_tag: consumer_tag}}, state) do
    if Map.has_key?(state.closing, consumer_tag) do
      :ok = AMQP.Channel.close(state.closing[consumer_tag])
      {:noreply, %{state | closing: Map.delete(state.closing, consumer_tag)}}
    else
      {:noreply, state}
    end
  end

  def handle_info({:basic_deliver, payload, meta}, state) do
    queue = find_queue_by_tag(meta.consumer_tag, state)
    if queue != nil do
      if !MapSet.member?(state.paused, queue.type) do
        {:ok, _pid} = WorkerSupervisor.start_child(state.application, queue.channel, payload, meta)
        {:noreply, state}
      else
        state = pause_queue(queue, state)
        AMQP.Basic.nack(queue.channel, meta.delivery_tag)
        {:noreply, state}
      end
    else
      if Map.has_key?(state.closing, meta.consumer_tag) do
        AMQP.Basic.nack(state.closing[meta.consumer_tag], meta.delivery_tag)
      end
      {:noreply, state}
    end
  end

  def handle_info(:timeout, state) do
    {:noreply, do_reconfigure(state, state.application)}
  end


  ## Internal functions

  defp reconfigure_valid?(application, state) do
    if application.id == state.application.id do
      :ok
    else
      {:error, :application_id_change}
    end
  end

  defp do_reconfigure(state, application) do

    existing_queue_types = (for q <- state.queues, do: q.type) |> Enum.into(MapSet.new)
    new_queue_types = (for q <- application.queues, do: q.type) |> Enum.into(MapSet.new)

    pick = fn(types, queues) ->
      queues |> Enum.filter(fn(q) -> MapSet.member?(types, q.type) end)
    end

    # close channels of queues that are not in application.queues
    closing = MapSet.difference(existing_queue_types, new_queue_types)
    |> pick.(state.queues)
    |> Enum.map(fn(q) ->
      if q.consumer_tag != nil do
        {:ok, _} = AMQP.Basic.cancel(q.channel, q.consumer_tag)
      end
      {q.consumer_tag, q.channel}
    end)
    |> Enum.into(%{})

    # reconfigure channels that have changed
    existing_queues = MapSet.intersection(new_queue_types, existing_queue_types)
    |> pick.(state.queues)
    |> Enum.map(fn(q) ->
      # currently, max_workers is the only channel property that can change
      new_q = Enum.find(application.queues, &(&1.type == q.type))
      :ok = AMQP.Basic.qos(q.channel, prefetch_count: new_q.max_workers)
      %{q | max_workers: new_q.max_workers}
    end)

    # open channels of queues that are in new queues but not in application queues
    new_queues = MapSet.difference(new_queue_types, existing_queue_types)
    |> pick.(application.queues)
    |> Enum.map(fn(q) ->
      {:ok, channel} = Roger.AMQPClient.open_channel()
      :ok = AMQP.Basic.qos(channel, prefetch_count: q.max_workers)
      #      if !MapSet.member?(state.paused, q.type) do
      consume(%Queue{q | channel: channel}, state)
      #      else
      #        %Queue{q | channel: channel}
      #      end
    end)

    queues = (existing_queues ++ new_queues) |> Enum.sort(&(&1.type < &2.type))

    %State{state | application: application, queues: queues, closing: closing}
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
      queues = Enum.map(state.queues, fn(q) ->
        if q.consumer_tag == queue.consumer_tag do
          %{q | consumer_tag: nil}
        else
          q
        end
      end)
      %{state | queues: queues}
    else
      state
    end
  end

  defp resume_queue(type, state) do
    if MapSet.member?(state.paused, type) do
      queue = find_queue_by_type(type, state)
      queues = Enum.map(state.queues, fn(q) ->
        if q.type == queue.type do
          consume(q, state)
        else
          q
        end
      end)
      %{state |
        paused: MapSet.delete(state.paused, type),
        queues: queues}
    else
      state
    end
  end

  defp consume(queue, state) do
    queue_name = Queue.make_name(state.application, queue.type)
    # FIXME: do something with stats?
    {:ok, _stats} = AMQP.Queue.declare(queue.channel, queue_name)
    {:ok, consumer_tag} = AMQP.Basic.consume(queue.channel, queue_name)
    %Queue{
      queue |
      consumer_tag: consumer_tag,
      confirmed: false}
  end
end
