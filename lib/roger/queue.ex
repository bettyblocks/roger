defmodule Roger.Queue do
  @moduledoc """
  Functions related to queues.
  """

  alias Roger.Queue

  @type t :: %__MODULE__{}

  defstruct type: nil, max_workers: nil, consumer_tag: nil, channel: nil, confirmed: false, channel_ref: nil

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
    connection_name = Application.get_env(:roger, :connection_name)

    with {:ok, amqp_conn} <- AMQP.Application.get_connection(connection_name),
         {:ok, channel} <- AMQP.Channel.open(amqp_conn, {AMQP.DirectConsumer, self()}) do
      ref = Process.monitor(channel.pid)
      :ok = AMQP.Basic.qos(channel, prefetch_count: queue.max_workers)
      {:ok, %Queue{queue | channel: channel, channel_ref: ref}}
    end
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
    channel_name = Application.get_env(:roger, :channel_name)
    {:ok, channel} = AMQP.Application.get_channel(channel_name)
    queue = make_name(partition_id, queue_type)
    result = AMQP.Queue.purge(channel, queue)

    result
  end
end
