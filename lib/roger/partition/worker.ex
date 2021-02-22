defmodule Roger.Partition.Worker do
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

  alias Roger.{Job, GProc, Queue, Partition.Retry}
  alias Roger.Partition.Global

  # after how long the wait queue for execution_key-type jobs expires
  @execution_waiting_expiry 1800 * 1000

  use GenServer, restart: :transient

  def start_link(worker_input) do
    GenServer.start_link(__MODULE__, worker_input)
  end

  def name(job_id) do
    {:roger_job_worker, job_id}
  end

  ## Server interface

  defmodule State do
    @moduledoc false
    defstruct partition_id: nil, meta: nil, raw_payload: nil, channel: nil, worker_task_pid: nil, job: nil
  end

  def init([partition_id, channel, payload, meta]) do
    state = %State{
      partition_id: partition_id,
      channel: channel,
      meta: meta,
      raw_payload: payload
    }

    Process.flag(:trap_exit, true)
    {:ok, state, 0}
  end

  @doc """
  This will make sure the worker task is killed when the worker get's stopped
  """
  @spec terminate(any(), State.t()) :: any()
  def terminate(_reason, state) do
    if state.worker_task_pid do
      Process.exit(state.worker_task_pid, :kill)
    end
  end

  @doc """
  This function starts processing the job as soon as the worker GenServer is started up.
  """
  @spec handle_info(:timeout, State.t()) :: {:noreply, State.t()} | {:stop, :normal, State.t()}
  def handle_info(:timeout, state) do
    case Job.decode(state.raw_payload) do
      {:ok, job} ->
        job = %Job{job | started_at: Roger.now()}

        cond do
          Global.cancelled?(state.partition_id, job.id, :remove) ->
            job_cancel(job, state)
            {:stop, :normal, state}

          job_waiting?(job, state) ->
            job_waiting(job, state)
            {:stop, :normal, state}

          true ->
            pid = job_startup(job, state)
            {:noreply, %{state | worker_task_pid: pid, job: job}}
        end

      {:error, message} ->
        # Decode error
        Logger.debug("Job decoding error: #{inspect(message)} #{inspect(state.raw_payload)}")
        job_done(nil, :ack, state)
        {:stop, :normal, state}
    end
  end

  @doc """
  When job is finished it sends a message to the GenServer to finish off the worker task.
  """
  @spec handle_info(:job_finished, State.t()) :: {:stop, :normal, State.t()}
  def handle_info(:job_finished, state) do
    {:stop, :normal, state}
  end

  @doc """
  When job has errors the async job task sends a message to this worker to correctly unregister and shutdown the worker.
  """
  @spec handle_info(:job_errored, State.t()) :: {:stop, :normal, State.t()}
  def handle_info(:job_errored, state) do
    state.job.id
    |> name()
    |> GProc.unregp()

    GProc.unregp({:roger_job_worker_meta, state.partition_id, state.job.id})
    {:stop, :normal, state}
  end

  @doc """
  If a timeout is set on the job and the job exceeds the timeout this method is called and correctly shuts down the job.
  """
  @spec handle_info(:handle_job_timeout, State.t()) :: {:stop, :normal, State.t()}
  def handle_info(:handle_job_timeout, %{worker_task_pid: pid, job: job} = state) when is_pid(pid) do
    Process.exit(pid, :kill)
    handle_error(job, {:timeout, "Job stopped because of timeout"}, nil, state, nil)
    {:stop, :normal, state}
  end

  @doc """
  This handle a hard crash
  """
  @spec handle_info({:DOWN, reference(), :process, pid(), String.t()}, State.t()) :: {:stop, :normal, State.t()}
  def handle_info({:DOWN, _ref, :process, _child, reason}, state) do
    handle_error(state.job, {:worker_crash, reason}, nil, state, nil)
    {:stop, :normal, state}
  end

  @doc """
  This is called when job needs to be cancelled it kills running job and runs the timeout task to correctly finish the job.
  """
  @spec handle_call(:cancel_job, any(), State.t()) :: {:reply, :ok, State.t(), 0}
  def handle_call(:cancel_job, _source, state) do
    Process.exit(state.worker_task_pid, :kill)
    {:reply, :ok, state, 0}
  end

  defp execute_job(job, state, parent) do
    before_run_state = callback(:before_run, [state.partition_id, job])

    try do
      result = Job.execute(job)

      job_done(job, :ack, state)

      callback(:after_run, [state.partition_id, job, result, before_run_state])
    catch
      type, exception ->
        handle_error(job, {type, exception}, before_run_state, state, __STACKTRACE__)
        send(parent, :job_errored)
    end
  end

  defp handle_error(job, {type, exception}, before_run_state, state, stacktrace) do
    cb =
      with true <- Job.retryable?(job),
           {:ok, :buried} <- Retry.retry(state.channel, state.partition_id, job) do
        :on_buried
      else
        _ -> :on_error
      end

    job_done(job, :ack, state)
    callback(cb, [state.partition_id, job, {type, exception}, stacktrace, before_run_state])
  end

  defp job_startup(job, state) do
    GProc.regp(name(job.id))
    GProc.regp({:roger_job_worker_meta, state.partition_id, job.id}, job)
    parent = self()

    {pid, _ref} =
      spawn_monitor(fn ->
        execute_job(job, state, parent)
        send(parent, :job_finished)
      end)

    if job.max_execution_time != :infinity do
      Process.send_after(self(), :handle_job_timeout, job.max_execution_time * 1000)
    end

    pid
  end

  defp job_waiting?(job, state) do
    job.execution_key != nil && Global.executing?(state.partition_id, job.execution_key, :add)
  end

  defp job_waiting(job, state) do
    # put job in the waiting queue,
    :ok = put_execution_waiting(job, state)
    # then ack it.
    AMQP.Basic.ack(state.channel, state.meta.delivery_tag)
  end

  defp job_cancel(job, state) do
    callback(:on_cancel, [state.partition_id, job])
    job_done(job, :ack, state)
  end

  # Ran at the end of the job, either ack'ing or nack'ing the message.
  defp job_done(job, ack_or_nack, state) do
    if job != nil do
      if job.queue_key != nil do
        :ok = Global.remove_queued(state.partition_id, job.queue_key)
      end

      if job.execution_key != nil do
        # mark as "free"
        :ok = Global.remove_executed(state.partition_id, job.execution_key)
        # check if there are any messages in the waiting queue
        check_execution_waiting(job, state)
      end
    end

    meta = state.meta

    if meta != nil do
      if Process.alive?(state.channel.pid) do
        Kernel.apply(AMQP.Basic, ack_or_nack, [state.channel, meta.delivery_tag])
      end
    end
  end

  # Run the given worker callback, if a callback module has been defined.
  defp callback(callback, args) when is_atom(callback) do
    mod = Application.get_env(:roger, :callbacks)
    # Make sure module is loaded so function_exported? works correctly
    Code.ensure_loaded(mod)

    if mod != nil do
      try do
        # We never want the callback to crash the worker process.
        if function_exported?(mod, callback, length(args)) do
          Kernel.apply(mod, callback, args)
        else
          nil
        end
      catch
        :exit = t, e ->
          Logger.error("Worker error in callback function #{mod}.#{callback}: #{t}:#{e}")
      end
    end
  end

  # Put in the waiting queue
  defp put_execution_waiting(job, state) do
    Job.enqueue(job, state.partition_id, execution_waiting_queue(job, state, :unprefixed))
  end

  # Get the next message from the job's execution waiting queue, and
  # enqueues it back on the Job's main queue, if there is any
  defp check_execution_waiting(job, state) do
    name = execution_waiting_queue(job, state)

    case AMQP.Basic.get(state.channel, name) do
      {:ok, payload, meta} ->
        # enqueue the job again
        {:ok, job} = Job.decode(payload)
        :ok = Job.enqueue(job, state.partition_id)
        # ack it to have it removed from waiting queue
        :ok = AMQP.Basic.ack(state.channel, meta.delivery_tag)

      {:empty, _} ->
        # FIXME delete waiting queue when empty - this can error
        :ok
    end
  end

  # Return the name of the execution waiting queue. The queue gets
  # declared on the AMQP side as well. Returns the queue either
  # prefixed with the partition or unprefixed.
  defp execution_waiting_queue(job, state, return \\ :prefixed) do
    bare_name = "execution-waiting-#{job.execution_key}"
    name = Queue.make_name(state.partition_id, bare_name)

    {:ok, _} =
      AMQP.Queue.declare(state.channel, name, durable: true, arguments: [{"x-expires", @execution_waiting_expiry}])

    case return do
      :prefixed -> name
      :unprefixed -> bare_name
    end
  end
end
