defmodule Roger.PartitionSupervisor do
  @moduledoc """
  The supervisor for all partitions.
  """

  use DynamicSupervisor

  def start_link([]) do
    DynamicSupervisor.start_link(__MODULE__, [], name: __MODULE__)
  end

  def init([]) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  def start_child(partition) do
    DynamicSupervisor.start_child(__MODULE__, {Roger.Partition.ContainingSupervisor, [partition]})
  end

  def stop_child(pid) do
    DynamicSupervisor.terminate_child(__MODULE__, pid)
  end
end
