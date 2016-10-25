defmodule Roger.WorkerTest do
  use ExUnit.Case
  #doctest Roger.Worker

  alias Roger.{Application, Queue, Application.Worker, Application.WorkerSupervisor}

  # defmodule TestWorkerCallback do
  #   use Roger.Worker.Callback
  # end

  setup do
    Elixir.Application.put_env(:roger, :callbacks, worker: TestWorkerCallback)
    Process.register(self(), :testcase)

    app = %Application{id: "test", queues: [Queue.define(:default, 10)]}
    {:ok, pid} = Application.start(app)

    {:ok, %{app: app}}
  end

  test "start worker in application worker supervisor", %{app: app} do

    {:ok, _pid} = WorkerSupervisor.start_child(app, "payload", nil)

    :timer.sleep 500

  end
end
