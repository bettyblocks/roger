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

  defp receive_list([]), do: :ok

  defp receive_list([msg | rest]) do
    receive do
      ^msg ->
        receive_list(rest)

      _other ->
        receive_list([msg | rest])
    after
      1000 ->
        :error
    end
  end

  test "jobs with execution key get executed sequentially" do
    # {:ok, channel} = Roger.AMQPClient.open_channel
    # use AMQP
    # on_exit fn -> Queue.purge(channel, "test-execution-waiting-a") end

    # Process.register(self(), Roger.Job.UniqueExecutionTest)
    # {:ok, _pid} = Roger.Partition.start(@app, [default: 10])

    {:ok, job} = Roger.Job.create(MyJob, 1)
    :ok = Roger.Job.enqueue(job, @app)
    :timer.sleep(1)
    {:ok, job} = Roger.Job.create(MyJob, 2)
    :ok = Roger.Job.enqueue(job, @app)
    :timer.sleep(1)
    {:ok, job} = Roger.Job.create(MyJob, 3)
    :ok = Roger.Job.enqueue(job, @app)
    :timer.sleep(1)

    assert :ok == receive_list(start: 1, stop: 1, start: 2, stop: 2, start: 3, stop: 3)
  end
end
