defmodule Roger.PartitionSupervisor do
  @moduledoc """
  The supervisor for all partitions.
  """

  use Supervisor

  def start_link() do
    Supervisor.start_link(__MODULE__, [], name: __MODULE__)
  end

  def init([]) do
    children = [
      supervisor(Roger.Partition.ContainingSupervisor, [], restart: :transient)
    ]
    supervise(children, strategy: :simple_one_for_one)
  end

  def start_child(partition) do
    Supervisor.start_child(__MODULE__, [partition])
  end

  def stop_child(pid) do
    Supervisor.terminate_child(__MODULE__, pid)
  end

end
