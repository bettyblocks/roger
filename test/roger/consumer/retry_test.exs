defmodule Roger.Application.Consumer.RetryTest do
  use ExUnit.Case
  use Roger.AppCase, callbacks: [worker: Roger.Application.Consumer.RetryTest.Callbacks]

  defmodule Callbacks do
    use Roger.Application.Worker.Callback

    def on_error(_app, job, {:error, %RuntimeError{message: "fail!"}}, _state) do
      send(:testcase, {:retry, job.retry_count})
    end

  end

  defmodule Retryable do
    use Roger.Job
    require Logger

    def perform(_n) do
      raise RuntimeError, "fail!"
    end

    def retryable?(), do: true

  end

  test "retryable job" do

    {:ok, job} = Job.create(Retryable, 1)
    Job.enqueue(job, @app)

    for n <- 0..5 do
      assert_receive {:retry, ^n}, 200
    end
  end

end
