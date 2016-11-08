defmodule Roger.Application.NodeInfoTest do
  use ExUnit.Case
  use Roger.AppCase

  alias Roger.NodeInfo
  alias Roger.Application.Consumer

  defmodule SlowTestJob do
    use Job

    def perform(queue) do
      :timer.sleep 200
      send(:testcase, {:done, queue})
    end
  end

  test "get application info" do
    assert %{waiting: w, running: r} = NodeInfo.applications
    assert is_map(w)
    assert is_map(r)
  end

  test "get the running jobs" do
    :ok = Consumer.resume(@app, :default)

    {:ok, job} = Job.create(SlowTestJob, 1)
    :ok = Job.enqueue(job, "test")
    :timer.sleep 10

    info = NodeInfo.running_jobs
    assert info["test"] == NodeInfo.running_jobs("test")

    assert is_map(info)
    assert is_list(info["test"])
    jobs = info["test"]

    assert 1 == Enum.count(jobs)
    job = jobs |> hd

    assert job.started_at > 0
    assert (Roger.now - job.started_at) > 0
    assert job.module == SlowTestJob
    assert job.args == 1

    assert_receive {:done, 1}, 500
    :timer.sleep 10

    assert [] == NodeInfo.running_jobs()["test"]
    assert [] == NodeInfo.running_jobs("test")
  end

  test "get queued jobs" do
    :ok = Consumer.pause(@app, :default)

    apps = NodeInfo.running_applications

    assert apps[@app].default.paused

    {:ok, job} = Job.create(SlowTestJob, 2)
    :ok = Job.enqueue(job, "test")

    {:ok, job} = Job.create(SlowTestJob, 3)
    :ok = Job.enqueue(job, "test")
    :timer.sleep 10

    apps = NodeInfo.running_applications
    q = apps[@app].default

    assert q.message_count == 2
    assert q.consumer_count == 0

    jobs = NodeInfo.queued_jobs("test", :default)
    assert [a, b] = jobs
    assert a.args == 3
    assert b.args == 2

    assert a.queued_at > 0
    assert a.started_at == 0

    :ok = Consumer.resume(@app, :default)
    assert_receive {:done, 2}, 500
    assert_receive {:done, 3}, 500
  end

end
