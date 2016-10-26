defmodule Roger.Application.Consumer do
  @moduledoc """

  Processes incoming jobs for an application and spawns off the worker process.
  """

  require Logger
  alias Roger.{Queue, GProc, Application, Application.WorkerSupervisor}

  use GenServer

  def start_link(%Application{} = application) do
    GenServer.start_link(__MODULE__, [application], name: GProc.via(name(application)))
  end

  def ack(application, consumer_tag, delivery_tag) do
    GenServer.call(GProc.via(name(application)), {:ack_nack, :ack, consumer_tag, delivery_tag})
  end

  def nack(application, consumer_tag, delivery_tag) do
    GenServer.call(GProc.via(name(application)), {:ack_nack, :nack, consumer_tag, delivery_tag})
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

  defp name(%Application{id: id}) do
    {:app_job_consumer, id}
  end


  ## Server interface

  defmodule State do
    defstruct application: nil, channel: nil, context: nil, queues: []
  end

  def init([application]) do
    context = nil # FIXME application consumer callback?
    {:ok, %State{application: application, context: context}, 0}
  end

  def handle_call({:ack_nack, ack_or_nack, consumer_tag, delivery_tag}, _from, state) do
    reply = case find_queue_by_tag(consumer_tag, state) do
              nil -> {:error, :channel_not_found}
              q ->
                Kernel.apply(AMQP.Basic, ack_or_nack, [q.channel, delivery_tag])
            end
    {:reply, reply, state}
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

  def handle_info({:basic_consume_ok, %{consumer_tag: consumer_tag}}, state) do
    # Confirmation sent by the broker after registering this process as a consumer
    queues = List.foldr(state.queues, [], fn(q, acc) ->
      queue = %{q | confirmed: q.confirmed || q.consumer_tag == consumer_tag}
      [queue | acc]
    end)
    {:noreply, Map.put(state, :queues, queues)}
  end

  def handle_info({:basic_cancel_ok, _}, state) do
    # FIXME do something here?
    {:noreply, state}
  end

  def handle_info({:basic_deliver, payload, meta}, state) do
    {:ok, _pid} = WorkerSupervisor.start_child(state.application, payload, meta)
    {:noreply, state}
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
    MapSet.difference(existing_queue_types, new_queue_types)
    |> pick.(state.queues)
    |> Enum.each(fn(q) ->
      {:ok, _} = AMQP.Basic.cancel(q.channel, q.consumer_tag)
      :ok = AMQP.Channel.close(q.channel)
    end)

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
      queue_name = Queue.make_name(state.application, q.type)
      {:ok, channel} = Roger.AMQPClient.open_channel()
      :ok = AMQP.Basic.qos(channel, prefetch_count: q.max_workers)
      # FIXME: do something with stats?
      {:ok, _stats} = AMQP.Queue.declare(channel, queue_name)
      {:ok, consumer_tag} = AMQP.Basic.consume(channel, queue_name)
      %Queue{
        q |
        queue: queue_name,
        channel: channel,
        consumer_tag: consumer_tag,
        confirmed: false}
    end)

    queues = (existing_queues ++ new_queues) |> Enum.sort(&(&1.type < &2.type))

    %State{state | application: application, queues: queues}
  end

  defp find_queue_by_tag(consumer_tag, state) do
    state.queues |> Enum.find(&(&1.consumer_tag == consumer_tag))
  end

end
