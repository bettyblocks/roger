defmodule Roger.Job.WorkerTimeoutTest do
  use ExUnit.Case
  use Roger.AppCase

  alias Roger.Job

  defmodule OnErrorCallback do
    use Roger.Partition.Worker.Callback

    def on_error(_partition, _job, {error, _reason}, _, _) do
      send(Roger.Job.WorkerTimeoutTest, {:job_error, error})
    end
  end


  defmodule MyLongJob do
    use Roger.Job

    def perform([time]) do
      :timer.sleep(time)
      send(Roger.Job.WorkerTimeoutTest, :job_done)
    end

    def max_execution_time(), do: 100

  end

  test "job should not finish when over timeout" do
    Application.put_env(:roger, :callbacks, OnErrorCallback)
    {:ok, job} = Job.create(MyLongJob, [150])
    :ok = Job.enqueue(job, @app)

    refute_receive :job_done
    assert_receive {:job_error, :timeout}
  end

  test "jobs still complete inside timeout" do
    {:ok, job} = Job.create(MyLongJob, [50])
    :ok = Job.enqueue(job, @app)

    assert_receive :job_done
  end

end
