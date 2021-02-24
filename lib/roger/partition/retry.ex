defmodule Roger.Partition.Retry do
  @moduledoc """
  Implements the retry logic for jobs.

  Jobs are retried at a fixed number of delay intervals. By default,
  these are the following (in seconds):

  1, 3, 5, 10, 20, 35, 60, 100, 200, 400, 1000, 1800.

  To override these levels, set the following configuration:

      config :roger,
        retry_levels: [1, 10, 60]

  This sets 3 retry levels, the first time is a job retried after 1
  second, then after 10 seconds and finally after 60.

  ## Implementation

  For every retry level, a separate AMQP queue is made. The messages
  in the queue have a TTL value that is set to the retry delay. After
  the TTL expires, the messages are sent to the "dead letter
  exchange", which for this queue points to the original queue.

  The queues themselves also have an expiry so that when the queue is
  empty, it will be removed.
  """

  alias Roger.{Queue, Job}

  @default_levels [1, 3, 5, 10, 20, 35, 60, 100, 200, 400, 1000, 1800]
  @max_buried_queue_size Application.get_env(:roger, :max_buried_queue_size, 100)

  @doc """
  Given an AMQP channel and the partition, queues the given job for retry.
  """
  def retry(channel, partition, job) do
    {queue, expiration} = setup_retry_queue(channel, partition, job)

    payload = Job.encode(%Job{job | retry_count: job.retry_count + 1})

    opts_extra =
      case expiration do
        :buried -> []
        _ -> [expiration: Integer.to_string(expiration * 1000)]
      end

    AMQP.Basic.publish(channel, "", queue, payload, Job.publish_opts(job, partition) ++ opts_extra)
    {:ok, expiration}
  end

  defp setup_retry_queue(channel, partition, job) do
    levels = Application.get_env(:roger, :retry_levels, @default_levels)
    queue_type = Job.queue_type(job)

    expiration =
      if job.retry_count < Enum.count(levels) do
        :lists.nth(job.retry_count + 1, levels)
      else
        :buried
      end

    arguments = [
      {"x-dead-letter-exchange", ""},
      {"x-dead-letter-routing-key", Queue.make_name(partition, queue_type)}
    ]

    {queue_name, arguments} =
      if expiration == :buried do
        {Queue.make_name(partition, queue_type, ".buried"), [{"x-max-length", @max_buried_queue_size}]}
      else
        {Queue.make_name(partition, queue_type, ".retry.#{expiration}"),
         arguments ++ [{"x-expires", expiration * 1000 + 2000}]}
      end

    {:ok, _stats} = AMQP.Queue.declare(channel, queue_name, durable: true, arguments: arguments)
    {queue_name, expiration}
  end
end
