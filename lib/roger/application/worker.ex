defmodule Roger.Application.Worker do

  @moduledoc """

  Handles a single job

  """

  require Logger

  alias Roger.Job
  alias Roger.Application.Consumer

  use GenServer

  def start_link(application, payload, meta) do
    GenServer.start_link(__MODULE__, [application, payload, meta])
  end

  ## Server interface

  defmodule State do
    defstruct application: nil, job: nil, meta: nil, raw_payload: nil
  end

  def init([application, payload, meta]) do
    state = %State{application: application, meta: meta, raw_payload: payload}
    {:ok, state, 0}
  end

  def handle_info(:timeout, state) do
    meta = state.meta
    try do
      execute_job(state) # FIXME what to do with the return value?
      ack(meta, state)
    catch
      t, e ->
        Logger.error "Execution error: #{t}:#{inspect e}"
      # IO.inspect(System.stacktrace)
      nack(meta, state)
    end
    {:stop, :normal, state}
  end

  defp execute_job(state) do
    case Poison.decode(state.raw_payload, as: %Job{}) do
      {:ok, job} ->

        module = String.to_existing_atom(job.module)

        Logger.metadata(job: job.id)

        result = Kernel.apply(module, :perform, job.args)

        result
      {:error, _} = e ->
        raise RuntimeError, "Error deserializing job: #{inspect e}"
    end
  end

  defp ack(nil, _state), do: nil
  defp ack(meta, state) do
    Consumer.ack(state.application, meta.consumer_tag, meta.delivery_tag)
  end

  defp nack(nil, _state), do: nil
  defp nack(meta, state) do
    Consumer.nack(state.application, meta.consumer_tag, meta.delivery_tag)
  end

end
