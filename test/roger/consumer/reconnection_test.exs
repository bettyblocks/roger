defmodule Roger.Partition.Consumer.ReconnectionTest do
  use ExUnit.Case

  alias Roger.Job

  defmodule MyJob do
    use Roger.Job
    require Logger

    def perform(_n) do
      :timer.sleep 100
      send(Roger.Partition.Consumer.ReconnectionTest, :reconnect_job_done)
    end

  end

  @app "test"

  setup do
    Process.register(self(), Roger.Partition.Consumer.ReconnectionTest)
    {:ok, _pid} = Roger.Partition.start(@app, [default: 10])

    on_exit fn ->
      :ok = Application.stop :roger
      :ok = Application.start :roger
      :timer.sleep 200
    end

    :ok
  end

  test "reconnect after enqueue job" do
    {:ok, job} = Job.create(MyJob, 1)
    Job.enqueue(job, @app)
    :timer.sleep 10

    restart_amqp_connection()

    assert_receive :reconnect_job_done, 10000

  end


  # test "reconnect before enqueue job" do
  #   restart_amqp_connection()
  #   {:ok, job} = Job.create(MyJob, 1)
  #   Job.enqueue(job, app)
  #   assert_receive :reconnect_job_done, 200
  # end


  defp restart_amqp_connection do
    pid = GenServer.call(Roger.AMQPClient, :get_connection_pid)
    Process.exit(pid, :kill)
  end

end
