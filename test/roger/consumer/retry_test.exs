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

  test "retryable job" do
    Application.put_env(:roger, :retry_levels, [1,1,1])

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

  test "retry queue buried limit" do
    Application.put_env(:roger, :retry_levels, [0])
    {:ok, job} = Job.create(Retryable, 1)
    Enum.each(1..101, fn(_) ->
      Job.enqueue(job, @app)
    end)

    Enum.each(1..101, fn(_) ->
      assert_receive {:retry, :buried}, 1500
    end)
    queue_name = Queue.make_name("test", "default", ".buried")



    {:ok, channel} = Roger.AMQPClient.open_channel()
    {:ok, stats} = AMQP.Queue.status(channel, queue_name)

    assert stats.message_count == 100
  end

end
