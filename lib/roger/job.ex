defmodule Roger.Job do
  @moduledoc """
  Base module for implementing Roger jobs.

  To start, `use Roger.Job` in your module. The only required callback
  to implement is the `perform/1` function.

      defmodule TestJob do
        use Roger.Job
        def perform(_args) do
          # perform some work here...
        end
      end

  Other functions that can be implemented in a job module are the
  following:

  `queue_key/1` - Enforces job uniqueness. When returning a string
  from this function, Roger enforces that only one job per queue key
  can be put in the queue at the same time. Only when the job has left
  the queue (after it has been executed), it will be possible to
  enqueue a job with the same queue key again.

  `execution_key/1` - Enforces job execution serialization. When
  returning a string from this function, Roger enforces that not more
  than one job with the same job is executed concurrently. However, it
  is still possible to have multiple jobs with the same execution key
  enqueued, but jobs that have the same execution key will be put in a
  waiting queue and processed serially.

  `queue_type/1` - Specifies which partition queue the job will run
  on. By default, this function returns `:default`, the default queue
  type.

  `retryable?/0` - Specifies whether the job should be retried using
  an exponential backoff scheme. The default implementation returns
  false, meaning that jobs will not be retried.

  """

  @type t :: %__MODULE__{}

  @derive {Poison.Encoder, only: ~w(id module args queue_key execution_key retry_count started_at queued_at)a}
  defstruct id: nil,
            module: nil,
            args: nil,
            queue_key: nil,
            execution_key: nil,
            retry_count: 0,
            started_at: 0,
            queued_at: 0,
            max_execution_time: :infinity

  alias Roger.{Queue, Partition.Global, Job}

  require Logger

  @content_type "partition/x-erlang-binary"

  @doc """
  Enqueues a job in the given partition.
  """
  def enqueue(%__MODULE__{} = job, partition_id, override_queue \\ nil) do
    queue = Queue.make_name(partition_id, override_queue || queue_type(job))

    # Check the queue key; when there is a queue key and it is not
    # queued, immediately add it to the queue key set to prevent
    # races.
    if job.queue_key != nil and Global.queued?(partition_id, job.queue_key, :add) do
      {:error, :duplicate}
    else
      job = %Job{job | queued_at: Roger.now()}
      Roger.AMQPClient.publish("", queue, encode(job), Job.publish_opts(job, partition_id))
    end
  end

  @doc """
  Constructs the AMQP options for publishing the job
  """
  def publish_opts(%__MODULE__{} = job, partition_id) do
    [content_type: @content_type, persistent: true, message_id: job.id, app_id: partition_id]
  end

  @doc """
  To implement a job module, `use Roger.Job` in your module, and
  implement its required `perform/1` function.
  """
  defmacro __using__(_) do
    quote location: :keep do
      @behaviour Roger.Job

      @doc false
      def queue_type(_args), do: :default

      defoverridable queue_type: 1
    end
  end

  @callback queue_key(any) :: String.t()
  @callback execution_key(any) :: String.t()
  @callback queue_type(any) :: atom
  @callback perform(any) :: any
  @callback retryable?() :: true | false

  @doc """
  Ability to set max execution time of the job in seconds.
  The default is :infinity which will allow the job unlimited time to finish.
  Minimum value is 1 seconds.
  """
  @callback max_execution_time() :: integer() | :infinity

  @optional_callbacks queue_key: 1, execution_key: 1, retryable?: 0, max_execution_time: 0

  @doc """
  Creates a new job based on a job module.

  The given `module` must exist as an Elixir module and must be
  implementing the Job behaviour (`use Roger.Job`). Arguments can be
  passed by the `args` parameter as a list. Job `id` is a random hex assigned to the job.

  The function returns the Job struct, which can be sent off to the
  queues using `Job.enqueue/2`.

  ## Examples

      iex> {:ok, job} = Roger.Job.create(Roger.JobTest.SquareJob, [4])
      iex> job.__struct__
      Roger.Job
  """
  def create(module, args \\ [], id \\ generate_job_id()) when is_atom(module) do
    keys =
      ~w(queue_key execution_key)a
      |> Enum.map(fn prop ->
        if function_exported?(module, prop, 1) do
          {prop, Kernel.apply(module, prop, [args])}
        else
          {prop, nil}
        end
      end)
      |> Enum.into(%{})

    max_execution_time =
      if function_exported?(module, :max_execution_time, 0) do
        execution_time =
          case apply(module, :max_execution_time, []) do
            0 -> 1
            execution_time -> execution_time
          end

        %{max_execution_time: execution_time}
      else
        %{}
      end

    %__MODULE__{module: module, args: args, id: id}
    |> Map.merge(keys)
    |> Map.merge(max_execution_time)
    |> validate
  end

  defp generate_job_id do
    :crypto.strong_rand_bytes(20) |> Base.hex_encode32(case: :lower)
  end

  @doc """
  Executes the given job.

  This function is called from within a `Job.Worker` process, there's
  no need to call it yourself.
  """
  def execute(%__MODULE__{} = job) do
    Kernel.apply(job.module, :perform, [job.args])
  end

  @doc """
  Decode a binary payload into a Job struct, and validates it.
  """
  @spec decode(data :: binary) :: {:ok, Roger.Job.t()} | {:error, msg :: String.t()}
  def decode(payload) do
    try do
      {:ok, :erlang.binary_to_term(payload)}
    rescue
      ArgumentError ->
        {:error, "Job decoding error"}
    end
    |> validate
  end

  @doc """
  Encodes a job into a binary payload.
  """
  @spec encode(job :: Job.t()) :: binary
  def encode(job) do
    job |> :erlang.term_to_binary()
  end

  defp validate({:ok, job}), do: validate(job)
  defp validate({:error, _} = e), do: e

  defp validate(%__MODULE__{id: id}) when not is_binary(id) do
    {:error, "Job id must be set"}
  end

  defp validate(%__MODULE__{module: module}) when not is_atom(module) do
    {:error, "Job module must be an atom"}
  end

  defp validate(%__MODULE__{module: module} = job) do
    case Code.ensure_loaded(module) do
      {:error, :nofile} ->
        {:error, "Unknown job module: #{module}"}

      {:error, :embedded} ->
        Logger.error("Module not available: #{module}")
        {:error, "Module not loaded correctly: #{module}"}

      {:module, ^module} ->
        functions = module.__info__(:functions)

        case Enum.member?(functions, {:perform, 1}) do
          false ->
            {:error, "Invalid job module: #{module} does not implement Roger.Job"}

          true ->
            {:ok, job}
        end
    end
  end

  @doc """
  Given a job, return its queue type
  """
  def queue_type(%__MODULE__{} = job) do
    job.module.queue_type(job.args)
  end

  @doc """
  Given a job, return whether it's retryable or not.
  """
  def retryable?(%__MODULE__{} = job) do
    if function_exported?(job.module, :retryable?, 0) do
      job.module.retryable?()
    else
      false
    end
  end
end
