defmodule Roger.Partition.NodeInfoTest do
  use ExUnit.Case
  use Roger.AppCase

  alias Roger.NodeInfo
  alias Roger.Partition.Consumer

  setup do
    :timer.sleep(1000)
  end

  defmodule SlowTestJob do
    use Job

    def perform(queue) do
      :timer.sleep(200)
      send(Roger.Partition.NodeInfoTest, {:done, queue})
    end
  end

  test "get partition info" do
    assert %{waiting: w, running: r} = NodeInfo.partitions()
    assert is_map(w)
    assert is_map(r)
  end

  test "get the running jobs" do
    :ok = Consumer.pause(@app, :default)

    :timer.sleep(50)

    {:ok, job} = Job.create(SlowTestJob, 1)
    :ok = Job.enqueue(job, @app)

    :timer.sleep(50)

    :ok = Consumer.resume(@app, :default)

    # The job only runs for a short while, so poll for it rather than
    # sleeping a fixed amount and hoping it has started by then.
    info = await_running_jobs(1)
    # assert info[@app] == NodeInfo.running_jobs(@app)

    assert is_map(info)
    assert is_list(info[@app])
    jobs = info[@app]

    assert 1 == Enum.count(jobs)
    job = jobs |> hd

    assert job.started_at > 0
    assert Roger.now() - job.started_at >= 0
    assert job.module == SlowTestJob
    assert job.args == 1

    assert_receive {:done, 1}, 500
    :timer.sleep(10)

    assert [] == NodeInfo.running_jobs()[@app]
    assert [] == NodeInfo.running_jobs(@app)
  end

  defp await_running_jobs(count, tries \\ 400) do
    info = NodeInfo.running_jobs()

    if tries == 0 or Enum.count(info[@app] || []) == count do
      info
    else
      :timer.sleep(5)
      await_running_jobs(count, tries - 1)
    end
  end

  test "queue info" do
    :ok = Consumer.pause(@app, :default)

    {:ok, job} = Job.create(SlowTestJob, 4)
    :ok = Job.enqueue(job, @app)

    # Pausing a queue only cancels the consumer on the broker once a job is
    # delivered to it, so wait for the consumer to actually be gone.
    partition = await_paused()

    assert partition[:default][:consumer_count] == 0
    assert partition[:default][:max_workers] == 10
    assert partition[:default][:message_count] > 0
    assert partition[:default][:paused] == true

    :ok = Consumer.resume(@app, :default)
    assert_receive {:done, 4}, 2_000
  end

  defp await_paused(tries \\ 100) do
    partition = NodeInfo.running_partitions()[@app]

    if tries == 0 or partition[:default][:consumer_count] == 0 do
      partition
    else
      :timer.sleep(10)
      await_paused(tries - 1)
    end
  end
end
