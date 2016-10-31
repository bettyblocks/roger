defmodule Roger.Application.Worker do

  @moduledoc """

  Handles the decoding and execution of a single job.

  Besides running the job, various administrative tasks need to be
  performed as well, namely:

  - Check whether the job has not been cancelled in the meantime

  - Check whether another job is currently running with the same
    execution_key, and if so, delay this current job until the
    currently running one finishes

  - On job failure, the job needs to be queued in the retry queue, if
    the job is marked retryable. By default, jobs are *not* retried.

  """

  require Logger

  alias Roger.{Job, GProc, Queue, Application.Retry}
  alias Roger.Application.StateManager

  use GenServer

  def start_link(application, channel, payload, meta) do
    GenServer.start_link(__MODULE__, [application, channel, payload, meta])
  end

  def name(job_id) do
    {:roger_job_worker, job_id}
  end

  ## Server interface

  defmodule State do
    defstruct application: nil, meta: nil, raw_payload: nil, channel: nil
  end

  def init([application, channel, payload, meta]) do
    state = %State{
      application: application,
      channel: channel,
      meta: meta,
      raw_payload: payload}
    {:ok, state, 0}
  end

  def handle_info(:timeout, state) do
    case Job.decode(state.raw_payload) do
      {:ok, job} ->
        if StateManager.cancelled?(state.application, job.id, :remove) do
          callback(:on_cancel, [state.application, job])
          job_done(job, :ack, state)
        else

          if job.execution_key != nil and StateManager.executing?(state.application, job.execution_key, :add) do
            # put job in the waiting queue,
            :ok = put_execution_waiting(job, state)
            # then ack it.
            AMQP.Basic.ack(state.channel, state.meta.delivery_tag)
          else
            GProc.regp(name(job.id))
            before_run_state = callback(:before_run, [state.application, job])
            try do
              result = Job.execute(job)
              job_done(job, :ack, state)

              callback(:after_run, [state.application, job, result, before_run_state])
            catch
              t, e ->
                #Logger.error "Execution error: #{t}:#{inspect e}"
              cb = if Job.retryable?(job) do
                case Retry.retry(state.channel, state.application, job) do
                  {:ok, :buried} -> :on_buried
                  {:ok, _expiration} -> :on_error
                end
              else
                :on_error
              end

              job_done(job, :ack, state)
              callback(cb, [state.application, job, {t, e}, before_run_state])
            end
          end
        end
      {:error, message} ->
        # Decode error
        Logger.debug "JSON decoding error: #{inspect message}"
        job_done(nil, :ack, state)
    end
    {:stop, :normal, state}
  end

  # Ran at the end of the job, either ack'ing or nack'ing the message.
  defp job_done(job, ack_or_nack, state) do

    if job != nil do
      if job.queue_key != nil do
        :ok = StateManager.remove_queued(state.application, job.queue_key)
      end

      if job.execution_key != nil do
        # mark as "free"
        :ok = StateManager.remove_executed(state.application, job.execution_key)
        # check if there are any messages in the waiting queue
        check_execution_waiting(job, state)
      end
    end

    meta = state.meta
    if meta != nil do
      Kernel.apply(AMQP.Basic, ack_or_nack, [state.channel, meta.delivery_tag])
    end
  end

  # Run the given worker callback, if a callback module has been defined.
  defp callback(callback, args) when is_atom(callback) do
    mod = Application.get_env(:roger, :callbacks, [])[:worker]
    if mod != nil do
      try do
        # We never want the callback to crash the worker process.
        Kernel.apply(mod, callback, args)
      catch
        :exit=t, e ->
          Logger.error "Worker error in callback function #{mod}.#{callback}: #{t}:#{e}"
      end
    end
  end

  # Put in the waiting queue
  defp put_execution_waiting(job, state) do
    Job.enqueue(job, state.application, execution_waiting_queue(job, state, :unprefixed))
  end

  # Get the next message from the job's execution waiting queue, and
  # enqueues it back on the Job's main queue, if there is any
  defp check_execution_waiting(job, state) do
    name = execution_waiting_queue(job, state)
    case AMQP.Basic.get(state.channel, name) do
      {:ok, payload, meta} ->
        # enqueue the job again
        {:ok, job} = Job.decode(payload)
        :ok = Job.enqueue(job, state.application)
        # ack it to have it removed from waiting queue
        :ok = AMQP.Basic.ack(state.channel, meta.delivery_tag)
      {:empty, _} ->
        # FIXME delete waiting queue when empty - this can error
        :ok
    end
  end

  # Return the name of the execution waiting queue. The queue gets
  # declared on the AMQP side as well. Returns the queue either
  # prefixed with the application or unprefixed.
  defp execution_waiting_queue(job, state, return \\ :prefixed) do
    bare_name = "execution-waiting-#{job.execution_key}"
    name = Queue.make_name(state.application, bare_name)
    {:ok, _} = AMQP.Queue.declare(state.channel, name, arguments: [{"x-expires", 1800}])
    case return do
      :prefixed -> name
      :unprefixed -> bare_name
    end
  end

end
