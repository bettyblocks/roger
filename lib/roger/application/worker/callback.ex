defmodule Roger.Application.Worker.Callback do

  defmacro __using__(_) do
    quote do
      @behaviour unquote(__MODULE__)

      def before_run(_application, _job), do: nil
      def after_run(_application, _job, _result, _before_run_state), do: nil

      def on_error(_application, _job, _error, _before_run_state), do: nil

      defoverridable before_run: 2, after_run: 4, on_error: 4

    end
  end

  @callback before_run(Roger.Application.t, Roger.Job.t) :: any
  @callback after_run(Roger.Application.t, Roger.Job.t, any, any) :: any
  @callback on_error(Roger.Application.t, Roger.Job.t, any, any) :: any

end
