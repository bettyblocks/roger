defmodule Roger.Partition.Consumer.RetryTest do
  use ExUnit.Case
  use Roger.AppCase, callbacks: Roger.Partition.Consumer.RetryTest.Callbacks

  defmodule Callbacks do
    use Roger.Partition.Worker.Callback

    def on_error(_app, job, {:error, %RuntimeError{message: "fail!"}}, _stack, _state) do
      send(Roger.Partition.Consumer.RetryTest, {:retry, job.retry_count})
    end

    def on_buried(_, _, _, _, _) do
      send(Roger.Partition.Consumer.RetryTest, {:retry, :buried})
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

  setup do
    Application.put_env(:roger, :retry_levels, [1,1,1])
  end

  test "retryable job" do

    {:ok, job} = Job.create(Retryable, 1)
    Job.enqueue(job, @app)

    for n <- 0..2 do
      if n > 0 do
        refute_receive {:retry, ^n}, 500
      end
      assert_receive {:retry, ^n}, 1500
    end

    assert_receive {:retry, :buried}, 1500
  end

end
