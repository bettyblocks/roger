defmodule Roger.Partition.Worker.Callback do
  @moduledoc """

  Provides hooks into the job execution lifecycle.

  Roger can be configured with callback modules for the job worker,
  which invokes functions on various places in the job's life
  cycle.

      config :roger,
        callbacks: MyWorkerModule

  In this scenario, the mentioned `MyWorkerModule` needs to *use*
  `Roger.Partition.Worker.Callback`:

      defmodule MyWorkerModule do
        use Roger.Partition.Worker.Callback
      end

  In this worker module, you can implement the functions `before_run/2`,
  `after_run/2`, `on_error/4`, `on_cancel/2` and `on_buried/2` to
  respond to job events.
  """

  defmacro __using__(_) do
    quote do
      @behaviour Roger.Partition.Worker.Callback
    end
  end

  @doc """
  Executed just before the job is going to run
  """
  @callback before_run(String.t(), Roger.Job.t()) :: any

  @doc """
  Executed just after the job has ran
  """
  @callback after_run(String.t(), Roger.Job.t(), any, any) :: any

  @doc """
  Executed when a job has exited with an error
  """
  @callback on_error(String.t(), Roger.Job.t(), {atom, String.t()}, any, any) :: any

  @doc """
  Executed when the job was cancelled

  A job can be cancelled either when it is still in the queue or while
  it is executing. The cancel callback will be only executed once.
  """
  @callback on_cancel(String.t(), Roger.Job.t()) :: any

  @doc """
  Executed when the job has failed its retry sequence

  Retryable jobs are retried in an exponential fashion. When the job
  has failed the retry sequence, e.g. it failed every time, it is put
  in a special queue called "buried". Upon placement in this queue,
  this callback gets executed.
  """
  @callback on_buried(partition_id :: String.t(), job :: Roger.Job.t(), any, any, any) :: any

  @optional_callbacks before_run: 2, after_run: 4, on_error: 5, on_cancel: 2, on_buried: 5
end
