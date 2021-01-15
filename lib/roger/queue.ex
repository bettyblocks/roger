defmodule Roger.Queue do
  @moduledoc """
  Functions related to queues.
  """

  alias Roger.{Queue, AMQPClient}

  @type t :: %__MODULE__{}

  defstruct type: nil, max_workers: nil, consumer_tag: nil, channel: nil, confirmed: false

  def define({type, max_workers}) do
    define(type, max_workers)
  end

  def define(type, max_workers) do
    %__MODULE__{type: type, max_workers: max_workers}
  end

  @doc """
  Setup channel with the queue options.
  This makes sure the channel prefetch count follows the queue max worker size.
  """
  @spec setup_channel(queue :: t) :: {atom, t}
  def setup_channel(%Queue{} = queue) do
    {:ok, channel} = Roger.AMQPClient.open_channel(self())
    :ok = AMQP.Basic.qos(channel, prefetch_count: queue.max_workers)
    {:ok, %Queue{queue | channel: channel}} |> IO.inspect(label: "open queue #{inspect(self())}")
  end

  @doc """
  Given a partition and a queue type, construct the Queue's name for RabbitMQ.
  """
  def make_name(partition_id, type, postfix \\ "") do
    "#{partition_id}-#{type}#{postfix}"
  end

  @doc """
  Flushes all messages on the given queue.
  """
  def purge(partition_id, queue_type) do
    {:ok, channel} = AMQPClient.open_channel()

    queue = make_name(partition_id, queue_type)
    result = AMQP.Queue.purge(channel, queue)

    :ok = AMQP.Channel.close(channel)
    result
  end
end
