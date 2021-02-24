defmodule Roger.NodeInfo do
  @moduledoc """
  Get information about the current partitions, queues and jobs on this node.
  """

  alias Roger.{Partition, Partition.Consumer, GProc}

  @doc """
  Retrieve combined partition info on all running and waiting partitions, on this node.
  """
  def partitions() do
    %{waiting: waiting_partitions(), running: running_partitions()}
  end

  @doc """
  Retrieve all partitions that are currently started on this node.
  """
  def running_partitions() do
    for {:app_supervisor, id} <- Roger.GProc.find_names({:app_supervisor, :_}) do
      {id, Consumer.get_queues(id)}
    end
    |> Enum.into(%{})
  end

  @doc """
  Retrieve all partitions that are currently waiting for start.

  When an partition is waiting for start, it typically means that
  the partition had trouble starting (e.g. due to a failed AMQP
  connection). When this is the case, the partition will be retried
  regularly.
  """
  def waiting_partitions() do
    GenServer.call(Partition, :waiting_partitions)
  end

  @doc """
  Retrieve all jobs that are currently running on this node.
  """
  def running_jobs() do
    running_partitions()
    |> Enum.map(fn {id, _queues} ->
      {id, running_jobs(id)}
    end)
    |> Enum.into(%{})
  end

  @doc """
  Retrieve all running jobs for the given partition on this node.
  """
  def running_jobs(partition_id) do
    selector = {:roger_job_worker_meta, partition_id, :_}

    for {_pid, job} <- GProc.find_properties(selector) do
      job
    end
  end

  @doc """
  Retreive all the currently running partition ids.
  """
  def running_partition_ids() do
    for {:app_supervisor, id} <- Roger.GProc.find_names({:app_supervisor, :_}) do
      id
    end
  end

  @doc """
  Retreive all running worker pids on this node.
  """
  def running_worker_pids() do
    for {pid, _job} <- Roger.GProc.find_properties({:roger_job_worker_meta, :_, :_}) do
      pid
    end
  end
end
