defmodule Roger.Application.ConsumerTest do
  use ExUnit.Case

  doctest Roger.Application.Consumer

  alias Roger.{Application, Application.Consumer, Queue}

  test "consumer starting" do
    app = %Application{id: "test", queues: [Queue.define(:default, 10)]}
    {:ok, _pid} = Application.start(app)


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

end
