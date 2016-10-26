defmodule Roger.Application.Worker do

  @moduledoc """

  Handles a single job

  """

  require Logger

  alias Roger.{Job, GProc}
  alias Roger.Application.{Consumer, StateManager}

  use GenServer

  def start_link(application, payload, meta) do
    GenServer.start_link(__MODULE__, [application, payload, meta])
  end

  def name(job_id) do
    {:roger_job_worker, job_id}
  end

  ## Server interface

  defmodule State do
    defstruct application: nil, meta: nil, raw_payload: nil
  end

  def init([application, payload, meta]) do
    state = %State{application: application, meta: meta, raw_payload: payload}
    {:ok, state, 0}
  end

  def handle_info(:timeout, state) do
    meta = state.meta
    case Job.decode(state.raw_payload) do
      {:ok, job} ->
        if job.queue_key != nil do
          :ok = StateManager.remove_queued(state.application, job.queue_key)
        end

        if StateManager.cancelled?(state.application, job.id, :remove) do
          callback(:on_cancel, [state.application, job])
          ack(meta, state)
        else
          GProc.regp(name(job.id))
          before_run_state = callback(:before_run, [state.application, job])
          try do
            # FIXME do anything with the return value?
            result = Job.execute(job)
            ack(meta, state)

            callback(:after_run, [state.application, job, result, before_run_state])
          catch
            t, e ->
              #Logger.warn "Execution error: #{t}:#{inspect e}"
              # FIXME: retry?
              nack(meta, state)

            callback(:on_error, [state.application, job, {t, e}, before_run_state])
          end
        end
      {:error, message} ->
        # Decode error
        Logger.debug "JSON decoding error: #{inspect message}"
        ack(meta, state)
    end
    {:stop, :normal, state}
  end

  defp ack(nil, _state), do: nil
  defp ack(meta, state) do
    Consumer.ack(state.application, meta.consumer_tag, meta.delivery_tag)
  end

  defp nack(nil, _state), do: nil
  defp nack(meta, state) do
    Consumer.nack(state.application, meta.consumer_tag, meta.delivery_tag)
  end

  defp callback(callback, args) do
    mod = Application.get_env(:roger, :callbacks)[:worker]
    if mod != nil do
      try do
        # We never want the callback to crash the worker process.
        Kernel.apply(mod, callback, args)
      catch
        t, e ->
          Logger.error "Worker error in callback function #{mod}.#{callback}: #{t}:#{e}"
      end
    end
  end

end
