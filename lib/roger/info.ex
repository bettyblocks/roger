defmodule Roger.Info do
  @moduledoc """
  Get information about the current partitions, queues and jobs of the entire cluster.

  Most of the functions here are mirrored from `Roger.NodeInfo` but
  calls these function for each node through `Roger.System.call/2`.

  """

  alias Roger.{System, AMQPClient, Job}

  @doc """
  Retrieve combined partition info on all running and waiting partitions, over the entire cluster.
  """
  def partitions do
    gather(:partitions)
  end

  @doc """
  Retrieve all partitions that are currently started on all nodes in the cluster.
  """
  def running_partitions do
    gather(:running_partitions)
  end

  @doc """
  Retrieve all partitions that are currently waiting for start.
  """
  def waiting_partitions do
    gather(:waiting_partitions)
  end

  @doc """
  Retrieve all jobs that are currently running on the cluster.
  """
  def running_jobs do
    gather(:running_jobs)
  end

  @doc """
  Retrieve all running jobs for the given partition on the cluster.
  """
  def running_jobs(partition_id) do
    gather(:running_jobs, [partition_id])
  end

  @doc """
  Retrieve queued jobs for the given partition and queue.

  This basically does a `basic.get` AMQP command on the queue and
  requeues the message using a nack.
  """
  def queued_jobs(partition_id, queue_type, count \\ 100) do
    {:ok, channel} = AMQPClient.open_channel()

    queue = Roger.Queue.make_name(partition_id, queue_type)
    result = get_queue_messages(channel, queue, count)

    :ok = AMQP.Channel.close(channel)
    result
  end

  defp get_queue_messages(channel, queue, count) do
    get_queue_messages(channel, queue, count, [])
  end

  defp get_queue_messages(_, _, 0, result) do
    result
  end
  defp get_queue_messages(channel, queue, count, acc) do
    case AMQP.Basic.get(channel, queue, no_ack: false) do
      {:ok, payload, _meta} ->
        {:ok, job} = Job.decode(payload)
        get_queue_messages(channel, queue, count - 1, [job | acc])
      {:empty, _} ->
        acc
    end
  end


  defp gather(call, args \\ []) do
    {:ok, result} = System.call({:apply, Roger.NodeInfo, call}, args)
    result
  end

end
