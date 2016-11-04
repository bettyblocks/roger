defmodule Roger.Application do
  @moduledoc """
  A structure which defines a single roger "application".

  Roger implements multi-tenancy by dividing all its work between
  different Applications. (this name might be confusing - an OTP
  application is something different!)

  Each application has a unique, stable ID, a name and a list which
  defines its queues. each queue is defined by its type (an atom) and
  a max_workers value which sets the concurrency level.

  """

  @type t :: %__MODULE__{}

  defstruct id: nil, queues: []

  defdelegate start(app), to: Roger.ApplicationRegistry

end
