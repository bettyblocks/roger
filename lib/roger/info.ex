defmodule Roger.Info do

  alias Roger.System

  def gather(call, args \\ []) do
    {:ok, result} = System.call({:apply, Roger.NodeInfo, call}, args)
    result
  end

  def applications do
    gather(:applications)
  end

  def running_applications do
    gather(:running_applications)
  end

  def waiting_applications do
    gather(:waiting_applications)
  end

  def running_jobs do
    gather(:running_jobs)
  end

  def running_jobs(app_id) do
    gather(:running_jobs, [app_id])
  end

end
