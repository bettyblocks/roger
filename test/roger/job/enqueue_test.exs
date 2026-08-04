defmodule Roger.Job.EnqueueTest do
  use ExUnit.Case
  use Roger.AppCase

  alias Roger.Job

  defmodule MyCalculation do
    use Roger.Job

    def perform([num]) do
      send(Roger.Job.EnqueueTest, num * num)
    end
  end

  test "job enqueue" do
    {:ok, job} = Job.create(MyCalculation, [2])
    :ok = Job.enqueue(job, @app)

    # A quorum queue needs to replicate the job before it is handed to a
    # worker, which takes more than the 100ms assert_receive defaults to.
    assert_receive 4, 2_000
  end

  test "non-unique jobs can be enqueued multiple times" do
    {:ok, job} = Job.create(MyCalculation, [2])
    :ok = Job.enqueue(job, @app)
    :ok = Job.enqueue(job, @app)

    assert_receive 4, 2_000
    assert_receive 4, 2_000
  end
end
