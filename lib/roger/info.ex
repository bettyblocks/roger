defmodule Roger.Info do
  @moduledoc """
  Get information about the current applications, queues and jobs of the entire cluster.

  This mirrors most functions from `Roger.NodeInfo` but calls these
  function for each node through `Roger.System.call/2`.

  """

  alias Roger.System

  @doc """
  Retrieve combined application info on all running and waiting applications, over the entire cluster.
  """
  def applications do
    gather(:applications)
  end

  @doc """
  Retrieve all applications that are currently started on all nodes in the cluster.
  """
  def running_applications do
    gather(:running_applications)
  end

  @doc """
  Retrieve all applications that are currently waiting for start.
  """
  def waiting_applications do
    gather(:waiting_applications)
  end

  @doc """
  Retrieve all jobs that are currently running on the cluster.
  """
  def running_jobs do
    gather(:running_jobs)
  end

  @doc """
  Retrieve all running jobs for the given application on the cluster.
  """
  def running_jobs(app_id) do
    gather(:running_jobs, [app_id])
  end

  defp gather(call, args \\ []) do
    {:ok, result} = System.call({:apply, Roger.NodeInfo, call}, args)
    result
  end

end
