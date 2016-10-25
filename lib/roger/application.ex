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

  defstruct id: nil, name: nil, queues: []


  def start(%__MODULE__{} = application) do
    # start application supervision tree
    case Roger.ApplicationSupervisor.start_child(application) do
      {:ok, pid} -> {:ok, pid}
      {:error, {:already_started, pid}} ->
        :ok = Roger.Application.Consumer.reconfigure(application)
        {:ok, pid}
    end
  end

  def defined_applications() do
    callback_module.defined_applications()
  end

  def start_all() do
    defined_applications() |> Enum.each(&start/1)
  end

  def callback_module do
    Application.get_env(:roger, :callbacks)[:application]
  end

end
