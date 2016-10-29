defmodule Roger.Application.ConsumerTest do
  use ExUnit.Case
  use Roger.AppCase

  doctest Roger.Application.Consumer

  alias Roger.{Application, Application.Consumer, Queue, Job}

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
    def queue_type(queue), do: queue
  end


  test "pause/resume API", %{app: app} do

    :ok = Consumer.pause(app, :default)

    {:ok, job} = Job.create(TestJob, :default)

    Job.enqueue(job, app)
    :timer.sleep 10

    refute_receive {:done, "default"}

    :ok = Consumer.resume(app, :default)

    assert_receive {:done, "default"}

  end


  test "pause/resume state should survive reconfigure", %{app: app} do

    :ok = Consumer.pause(app, :default)


    {:ok, job} = Job.create(TestJob, :default)
    Job.enqueue(job, app)
    :timer.sleep 10

    :ok = Consumer.reconfigure(Map.put(app, :queues, []))

    :ok = Consumer.reconfigure(Map.put(app, :queues, [Queue.define(:default, 10)]))
    :timer.sleep 10

    refute_receive {:done, "default"}

    :ok = Consumer.resume(app, :default)

    assert_receive {:done, "default"}

  end




end
