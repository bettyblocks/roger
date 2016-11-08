defmodule Roger.Application.Global.StatePersister do
  @moduledoc """
  Behaviour for the persistence of the global application state
  """

  @callback init(String.t) :: :ok
  @callback store(String.t, binary) :: :ok
  @callback load(String.t) :: {:ok, binary} | {:error, term}

end
