defmodule Roger.Job.UniqueExecutionTest do
  use ExUnit.Case

  defmodule MyJob do
    use Roger.Job

    def perform(msg) do
      send(:testcase, {:start, msg})
      :timer.sleep 100
      send(:testcase, {:stop, msg})
      :timer.sleep 100
    end

    def execution_key(_) do
      "a"
    end

  end

  defp receive_list(list) do
    receive do
      msg ->
        receive_list([msg | list])
    after 1000 ->
        Enum.reverse(list)
    end
  end

  test "jobs with execution key get executed sequentially" do

    {:ok, channel} = Roger.AMQPClient.open_channel
    use AMQP
    on_exit fn -> Queue.purge(channel, "test-execution-waiting-a") end

    Process.register(self(), :testcase)
    app = %Roger.Application{id: "test", queues: [Roger.Queue.define(:default, 10)]}
    {:ok, _pid} = Roger.Application.start(app)


    {:ok, job} = Roger.Job.create(MyJob, 1)
    :ok = Roger.Job.enqueue(job, app)
    :timer.sleep 1
    {:ok, job} = Roger.Job.create(MyJob, 2)
    :ok = Roger.Job.enqueue(job, app)
    :timer.sleep 1
    {:ok, job} = Roger.Job.create(MyJob, 3)
    :ok = Roger.Job.enqueue(job, app)
    :timer.sleep 1

    received = receive_list([])
    #IO.puts "received: #{inspect received}"

    assert received == [start: 1, stop: 1, start: 2, stop: 2, start: 3, stop: 3]

  end

end
