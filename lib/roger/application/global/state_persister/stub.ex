defmodule Roger.Application.Global.StatePersister.Stub do
  @moduledoc """
  Stub module for global state persistence.

  This is the default implementation, which does not actually persist
  the global application state.

  """

  alias Roger.Application.Global.StatePersister

  @behaviour StatePersister

  def init(_id), do: :ok
  def load(_id) do
    {:error, :not_implemented}
  end

  def store(_id, _data), do: :ok

end
