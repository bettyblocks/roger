defmodule Roger.Worker.CallbacksTest do
  use ExUnit.Case
  use Roger.AppCase

  alias Roger.{Partition, Partition.WorkerSupervisor}

  defmodule TestJob do
    use Roger.Job

    def perform([]) do
      nil
    end

  end

  @payload :erlang.term_to_binary(%Job{id: "asdf", module: TestJob, args: []})

  defmodule BeforeRunWorkerCallback do
    use Roger.Partition.Worker.Callback

    def before_run(_app, _job) do
      send(Roger.Worker.CallbacksTest, :before_run_ok)
    end
  end

  test "test before-run worker callback" do
    Application.put_env(:roger, Roger.Partition.Worker, callbacks: BeforeRunWorkerCallback)
    {:ok, _pid} = WorkerSupervisor.start_child(@app, :channel, @payload, nil)

    receive do
      :before_run_ok -> :ok
    after 1000 ->
        flunk("before_run not executed")
    end
  end



  defmodule AfterRunWorkerCallback do
    use Roger.Partition.Worker.Callback

    def after_run(_app, _job, _result, _state) do
      send(Roger.Worker.CallbacksTest, :after_run_ok)
    end
  end

  test "test after-run worker callback" do
    Application.put_env(:roger, Roger.Partition.Worker, callbacks: AfterRunWorkerCallback)
    {:ok, _pid} = WorkerSupervisor.start_child(@app, :channel, @payload, nil)

    receive do
      :after_run_ok -> :ok
    after 1000 ->
        flunk("after_run not executed")
    end
  end

  @ref :erlang.term_to_binary(make_ref())
  def test_ref do
    @ref
  end

  defmodule BeforeAfterRunWorkerCallback do
    use Roger.Partition.Worker.Callback

    def before_run(_app, _job) do
      Roger.Worker.CallbacksTest.test_ref
    end

    def after_run(_app, _job, result, state) do
      ^result = nil # assertion
      send(Roger.Worker.CallbacksTest, {:after_run_ok, state})
    end
  end

  test "test before-and-after-run worker callbacks with state passing through" do
    Application.put_env(:roger, Roger.Partition.Worker, callbacks: BeforeAfterRunWorkerCallback)
    {:ok, _pid} = WorkerSupervisor.start_child(@app, :channel, @payload, nil)
    receive do
      {:after_run_ok, r} ->
        assert test_ref() == r
        :ok
    after 1000 ->
        flunk("after_run not executed correctly")
    end
  end

  ##

  defmodule ErrorJob do
    use Roger.Job
    def perform(_), do: raise RuntimeError, "foo"
  end

  defmodule OnErrorWorkerCallback do
    use Roger.Partition.Worker.Callback

    def on_error(_app, _job, error, stacktrace, _state) do
      true = is_list(stacktrace)
      [{Roger.Worker.CallbacksTest.ErrorJob, :perform, 1, _} | _] = stacktrace

      {:error, %RuntimeError{}} = error
      send(Roger.Worker.CallbacksTest, :on_error_ok)
    end
  end

  @payload :erlang.term_to_binary(%Job{id: "asdf", module: ErrorJob, args: []})

  test "test on_error worker callback" do
    Application.put_env(:roger, Roger.Partition.Worker, callbacks: OnErrorWorkerCallback)
    {:ok, _pid} = WorkerSupervisor.start_child(@app, :channel, @payload, nil)
    receive do
      :on_error_ok -> :ok
    after 1000 ->
        flunk("on_error not executed")
    end
  end


end
