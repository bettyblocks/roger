defmodule Roger.Application.Global.StatePersister do
  @moduledoc """
  Behaviour for the persistence of the global application state.

  See `Roger.Application.Global` on how to implement a custom persister module.
  """


  @doc """
  Called when the global state process starts.
  """
  @callback init(id :: String.t) :: :ok

  @doc """
  Called when the global state needs to be stored.
  """
  @callback store(id :: String.t, data :: binary) :: :ok

  @doc """
  Called when the global state needs to be loaded.
  """
  @callback load(id :: String.t) :: {:ok, binary} | {:error, term}

end
