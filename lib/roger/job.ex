defmodule Roger.Job do
  @moduledoc """
  Base module for implementing Roger jobs.

  To start, `use Roger.Job` in your module. The only required callback
  to implement is the `perform/1` function.

  """

  @type t :: %__MODULE__{}

  @derive {Poison.Encoder, only: ~w(id module args queue_key execution_key)a}
  defstruct id: nil, module: nil, args: nil, queue_key: nil, execution_key: nil

  alias Roger.{Application, Queue, Application.StateManager}

  require Logger

  @queue_types ~w(default dependent expression)a

  @doc """
  Enqueues a job in the given application.
  """
  def enqueue(%__MODULE__{} = job, %Application{} = application, override_queue \\ nil) do
    queue = Queue.make_name(application, override_queue || queue_type(job))

    # Check the queue key; when there is a queue key and it is not
    # queued, immediately add it to the queue key set to prevent
    # races.
    if job.queue_key != nil and StateManager.queued?(application, job.queue_key, :add) do
      {:error, :duplicate}
    else
      opts = [
        content_type: "application/json",
        persistent: true,
        message_id: job.id,
        app_id: application.id
      ]

      payload = Poison.encode!(job)
      Roger.AMQPClient.publish("", queue, payload, opts)
    end
  end

  @doc false
  defmacro __using__(_) do

    quote do

      def queue_key(_args), do: nil
      def execution_key(_args), do: nil
      def queue_type(_args), do: :default

      defoverridable queue_key: 1, execution_key: 1, queue_type: 1

      def perform(_args) do
        raise RuntimeError, "FIXME: implement #{unquote(__CALLER__.module)}.perform/1"
      end
      defoverridable perform: 1
    end

  end

  def create(module, args \\ [], id \\ nil) when is_atom(module) do
    keys =
      ~w(queue_key execution_key)a
      |> Enum.map(fn(prop) -> {prop, Kernel.apply(module, prop, [args])} end)
      |> Enum.into(%{})

    %__MODULE__{module: module, args: args, id: id || generate_job_id()}
    |> Map.merge(keys)
    |> validate
  end

  defp generate_job_id do
    :crypto.rand_bytes(20) |> Base.hex_encode32(case: :lower)
  end


  def execute(%__MODULE__{} = job) do
    Kernel.apply(job.module, :perform, [job.args])
  end

  def decode(payload) do
    Poison.decode(payload, as: %__MODULE__{})
    |> validate
  end

  defp validate({:ok, job}), do: validate(job)
  defp validate({:error, _} = e), do: e

  defp validate(%__MODULE__{id: id}) when not(is_binary(id)) do
    {:error, "Job id must be set"}
  end

  defp validate(%__MODULE__{module: module} = job) when is_binary(module) do
    # convert to atom
    try do
      validate(%{job | module: String.to_existing_atom(module)})
    rescue
      ArgumentError -> {:error, "Unknown job module: " <> module}
    end
  end

  defp validate(%__MODULE__{} = job) do
    {:ok, job}
  end

  def queue_type(%__MODULE__{} = job) do
    job.module.queue_type(job.args)
  end

end
