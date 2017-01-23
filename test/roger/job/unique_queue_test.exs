defmodule Roger.Job.UniqueQueueTest do
  use ExUnit.Case
  use Roger.AppCase

  defmodule MyJob do
    use Roger.Job

    def queue_key([msg]) do
      "key-#{msg}"
    end

    def perform([msg]) do
      :timer.sleep(10)
      send(Roger.Job.UniqueQueueTest, msg)
    end
  end

  test "job gets refused when queued twice" do

    {:ok, job} = Job.create(MyJob, ["job1"])

    :ok = Job.enqueue(job, @app)
    {:error, :duplicate} = Job.enqueue(job, @app)
    assert_receive "job1"

    # can receive again after job has been processed
    :ok = Job.enqueue(job, @app)
    {:error, :duplicate} = Job.enqueue(job, @app)
    {:error, :duplicate} = Job.enqueue(job, @app)
    {:error, :duplicate} = Job.enqueue(job, @app)
    {:error, :duplicate} = Job.enqueue(job, @app)
    assert_receive "job1"

    :ok = Job.enqueue(job, @app)
    assert_receive "job1"

  end

end
