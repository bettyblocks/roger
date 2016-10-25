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
    GenServer.call(GProc.via(name(application)), {:ack, consumer_tag, delivery_tag})
  end

  def nack(application, consumer_tag, delivery_tag) do
    GenServer.call(GProc.via(name(application)), {:nack, consumer_tag, delivery_tag})
  end

  def is_alive?(application) do
    GProc.is_alive(name(application))
  end

  defp name(%Application{id: id}) do
    {:app_job_consumer, id}
  end

  ## Server interface

  defmodule State do
    defstruct application: nil, channel: nil, context: nil, queues: nil
  end

  def init([application]) do
    context = nil # FIXME application consumer callback?
    {:ok, %State{application: application, context: context}, 0}
  end

  def handle_call({:ack, consumer_tag, delivery_tag}, _from, state) do
    AMQP.Basic.ack(find_queue_by_tag(consumer_tag, state).channel, delivery_tag)
    {:reply, :ok, state}
  end

  def handle_call({:nack, consumer_tag, delivery_tag}, _from, state) do
    AMQP.Basic.nack(find_queue_by_tag(consumer_tag, state).channel, delivery_tag)
    {:reply, :ok, state}
  end

  # Confirmation sent by the broker after registering this process as a consumer
  def handle_info({:basic_consume_ok, %{consumer_tag: _consumer_tag}}, state) do
    # FIXME Set queue confirmation status to true
    {:noreply, state}
  end

  def handle_info({:basic_deliver, payload, meta}, state) do

    queue = find_queue_by_tag(meta.consumer_tag, state.queues)
    Logger.warn "Executing job on queue: #{queue.type} (app: #{state.application.name})"

    {:ok, _pid} = WorkerSupervisor.start_child(state.application, payload, meta)

    {:noreply, state}
  end

  def handle_info(:timeout, state) do
    {:noreply, ensure_channel(state)}
  end


  ## Internal functions

  defp ensure_channel(state) do
    queues = state.application.queues
    |> Enum.map(fn(q) ->
      # FIXME basic.cancel all existing consumers;
      # FIXME close existing channels

      queue_name = Queue.make_name(state.application, q.type)

      {:ok, channel} = Roger.AMQPClient.open_channel()

      :ok = AMQP.Basic.qos(channel, prefetch_count: q.max_workers)

      {:ok, _stats} = AMQP.Queue.declare(channel, queue_name)

      # FIXME do something with stats?

      {:ok, consumer_tag} = AMQP.Basic.consume(channel, queue_name)

      %Queue{
        q |
        queue: queue_name,
        channel: channel,
        consumer_tag: consumer_tag,
        confirmed: false}
    end)

    %State{state | queues: queues}
  end

  defp find_queue_by_tag(consumer_tag, state) do
    state.queues |> Enum.find(&(&1.consumer_tag == consumer_tag))
  end

end
