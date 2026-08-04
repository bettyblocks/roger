defmodule Roger.Job.UniqueExecutionTest do
  use ExUnit.Case
  use Roger.AppCase

  defmodule MyJob do
    use Roger.Job

    def perform(msg) do
      send(Roger.Job.UniqueExecutionTest, {:start, msg})
      :timer.sleep(100)
      send(Roger.Job.UniqueExecutionTest, {:stop, msg})
      :timer.sleep(100)
    end

    def execution_key(_) do
      "a"
    end
  end

  # Collect the jobs that ran, asserting along the way that a job always
  # finishes before the next one starts.
  defp receive_sequentially(0), do: []

  defp receive_sequentially(count) do
    receive do
      {:start, msg} ->
        receive do
          {:stop, ^msg} -> [msg | receive_sequentially(count - 1)]
          other -> flunk("job #{msg} overlapped with #{inspect(other)}")
        after
          2_000 -> flunk("job #{msg} never finished")
        end
    after
      5_000 -> flunk("expected #{count} more job(s) to run")
    end
  end

  test "jobs with execution key get executed sequentially" do
    # {:ok, channel} = Roger.AMQPClient.open_channel
    # use AMQP
    # on_exit fn -> Queue.purge(channel, "test-execution-waiting-a") end

    # Process.register(self(), Roger.Job.UniqueExecutionTest)
    # {:ok, _pid} = Roger.Partition.start(@app, [default: 10])

    for msg <- [1, 2, 3] do
      {:ok, job} = Roger.Job.create(MyJob, msg)
      :ok = Roger.Job.enqueue(job, @app)
      :timer.sleep(1)
    end

    # The jobs that got parked on the execution key are requeued by separate
    # worker processes, so the order in which they resume is not defined -
    # only that they never run at the same time.
    assert [1, 2, 3] == receive_sequentially(3) |> Enum.sort()
  end
end
