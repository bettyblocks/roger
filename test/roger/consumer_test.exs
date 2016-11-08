defmodule Roger.Application.ConsumerTest do
  use ExUnit.Case
  use Roger.AppCase

  doctest Roger.Application.Consumer

  alias Roger.{Application, Application.Consumer, Job,
               Application.Global}

  test "consumer starting" do

    # Check whether application consumer is alive
    assert Consumer.is_alive?(@app)

    :timer.sleep 50

    %{default: queue} = Consumer.get_queues(@app)
    assert 10 = queue.max_workers
    assert 0 = queue.message_count

    :ok = Consumer.reconfigure(@app, [default: 20, fast: 40])

    queues = Consumer.get_queues(@app)

    assert 20 == queues.default.max_workers
    assert 40 == queues.fast.max_workers

    :ok = Consumer.reconfigure(@app, [fast: 10])

    queues = Consumer.get_queues(@app)

    assert 1 = Enum.count(Map.values(queues))
    assert 10 == queues.fast.max_workers
  end

  defmodule TestJob do
    use Job

    def perform(queue) do
      send(:testcase, {:done, queue})
    end
  end


  test "pause/resume API" do

    :ok = Consumer.pause(@app, :default)

    {:ok, job} = Job.create(TestJob, :job_1)

    Job.enqueue(job, @app)
    :timer.sleep 10

    refute_receive {:done, :job_1}

    :ok = Consumer.resume(@app, :default)

    assert_receive {:done, :job_1}

  end


  test "pause/resume state should survive reconfigure" do

    :ok = Consumer.pause(@app, :default)


    {:ok, job} = Job.create(TestJob, :job_2)
    Job.enqueue(job, @app)
    :timer.sleep 10


    :ok = Consumer.reconfigure(@app, [])

    :ok = Consumer.reconfigure(@app, [default: 10])
    :timer.sleep 10

    refute_receive {:done, :job_2}

    :ok = Consumer.resume(@app, :default)

    assert_receive {:done, :job_2}

  end


  test "pause/resume state through Global" do

    :ok = Global.queue_pause(@app, :default)
    :timer.sleep 50

    {:ok, job} = Job.create(TestJob, :job_3)
    Job.enqueue(job, @app)


    refute_receive {:done, :job_3}

    :ok = Global.queue_resume(@app, :default)

    assert_receive {:done, :job_3}

  end


  test "pause/resume state through Global, consumer restart in between" do

    :ok = Global.queue_pause(@app, :default)
    :timer.sleep 50

    {:ok, job} = Job.create(TestJob, :job_4)
    Job.enqueue(job, @app)

    pid = Roger.GProc.whereis({:app_job_consumer, "test"})
    Process.exit(pid, :normal)

    refute_receive {:done, :job_4}, 200

    :ok = Global.queue_resume(@app, :default)

    assert_receive {:done, :job_4}


  end




end
