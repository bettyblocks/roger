defmodule Roger.Application.Worker.Callback do
  @moduledoc """

  Provides hooks into the job execution lifecycle.

  Roger can be configured with callback modules for the job worker,
  which invokes functions on various places in the job's life
  cycle.

      config :roger, :callbacks,
        worker: MyWorkerModule

  In this scenario, the mentioned `MyWorkerModule` needs to *use*
  `Roger.Worker.Callback`:

      defmodule MyWorkerModule do
        use Roger.Worker.Callback
      end

  In this worker module, you can implement the functions `before_run/2`,
  `after_run/2`, `on_error/4`, `on_cancel/2` and `on_buried/2` to
  respond to job events.
  """

  defmacro __using__(_) do
    quote do
      @behaviour unquote(__MODULE__)

      def before_run(_application, _job), do: nil
      def after_run(_application, _job, _result, _before_run_state), do: nil

      def on_error(_application, _job, _error, _before_run_state), do: nil
      def on_cancel(_application, _job), do: nil

      def on_buried(_application, _job, _error, _before_run_state), do: nil

      defoverridable before_run: 2, after_run: 4, on_error: 4, on_cancel: 2

    end
  end

  @callback before_run(Roger.Application.t, Roger.Job.t) :: any
  @callback after_run(Roger.Application.t, Roger.Job.t, any, any) :: any
  @callback on_error(Roger.Application.t, Roger.Job.t, any, any) :: any
  @callback on_cancel(Roger.Application.t, Roger.Job.t) :: any
  @callback on_buried(Roger.Application.t, Roger.Job.t, any, any) :: any

end
