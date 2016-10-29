defmodule Roger.Application.ConsumerTest do
  use ExUnit.Case
  use Roger.AppCase, async: false

  doctest Roger.Application.Consumer

  alias Roger.{Application, Application.Consumer, Queue, Job,
               Application.StateManager}

  test "consumer starting", %{app: app} do

    # Check whether application consumer is alive
    assert Consumer.is_alive?(app)

    :timer.sleep 50

    [queue] = Consumer.get_queues(app)

    assert 10 = queue.max_workers

    app = Map.put(app, :queues, [%{queue | max_workers: 20}, Queue.define(:fast, 40)])
    :ok = Consumer.reconfigure(app)

    [default, fast] = Consumer.get_queues(app)

    assert 20 = default.max_workers
    assert 40 = fast.max_workers

    app = Map.put(app, :queues, [Queue.define(:fast, 10)])
    :ok = Consumer.reconfigure(app)

    [fast] = Consumer.get_queues(app)
    assert 10 = fast.max_workers
  end

  defmodule TestJob do
    use Job

    def perform(queue) do
      send(:testcase, {:done, queue})
    end
  end


  test "pause/resume API", %{app: app} do

    :ok = Consumer.pause(app, :default)

    {:ok, job} = Job.create(TestJob, :job_1)

    Job.enqueue(job, app)
    :timer.sleep 10

    refute_receive {:done, "job_1"}

    :ok = Consumer.resume(app, :default)

    assert_receive {:done, "job_1"}

  end


  test "pause/resume state should survive reconfigure", %{app: app} do

    :ok = Consumer.pause(app, :default)


    {:ok, job} = Job.create(TestJob, :job_2)
    Job.enqueue(job, app)
    :timer.sleep 10

    :ok = Consumer.reconfigure(Map.put(app, :queues, []))

    :ok = Consumer.reconfigure(Map.put(app, :queues, [Queue.define(:default, 10)]))
    :timer.sleep 10

    refute_receive {:done, "job_2"}

    :ok = Consumer.resume(app, :default)

    assert_receive {:done, "job_2"}

  end


  test "pause/resume state through StateManager", %{app: app} do

    :ok = StateManager.queue_pause(app, :default)
    :timer.sleep 50

    {:ok, job} = Job.create(TestJob, :job_3)
    Job.enqueue(job, app)


    refute_receive {:done, "job_3"}

    :ok = StateManager.queue_resume(app, :default)

    assert_receive {:done, "job_3"}

  end


  test "pause/resume state through StateManager, consumer restart in between", %{app: app} do

    :ok = StateManager.queue_pause(app, :default)
    :timer.sleep 50

     {:ok, job} = Job.create(TestJob, :job_4)
    Job.enqueue(job, app)

    # pid = Roger.GProc.whereis({:app_job_consumer, "test"})
    # Process.exit(pid, :kill)

    refute_receive {:done, "job_4"}

    :ok = StateManager.queue_resume(app, :default)

    assert_receive {:done, "job_4"}

  end




end
