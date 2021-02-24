defmodule Roger.Partition.Global.StatePersister.Stub do
  @moduledoc """
  Stub module for `Roger.Partition.Global` state persistence.

  This is the default implementation, which **does not** persist any
  global partition state.

  """

  alias Roger.Partition.Global.StatePersister

  @behaviour StatePersister

  def init(_id), do: :ok

  def load(_id) do
    {:error, :not_implemented}
  end

  def store(_id, _data), do: :ok
end
