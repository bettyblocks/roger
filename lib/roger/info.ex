defmodule Roger.Info do
  @moduledoc """
  Get information about the current partitions, queues and jobs of the entire cluster.

  This mirrors most functions from `Roger.NodeInfo` but calls these
  function for each node through `Roger.System.call/2`.

  """

  alias Roger.System

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

  defp gather(call, args \\ []) do
    {:ok, result} = System.call({:apply, Roger.NodeInfo, call}, args)
    result
  end

end
