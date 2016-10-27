defmodule Roger.WorkerTest do
  use ExUnit.Case
  #doctest Roger.Worker

  alias Roger.{Application, Queue, Application.WorkerSupervisor}

  setup do
    Process.register(self(), :testcase)

    app = %Application{id: "test", queues: [Queue.define(:default, 10)]}
    {:ok, _pid} = Application.start(app)

    {:ok, %{app: app}}
  end


  defmodule TestJob do
    use Roger.Job

    def perform([]) do
      send(:testcase, :job_ok)
    end

  end

  @payload ~s({"id": "123", "module": "Elixir.Roger.WorkerTest.TestJob", "args": []})

  test "start worker in application worker supervisor", %{app: app} do
    {:ok, _pid} = WorkerSupervisor.start_child(app, :channel, @payload, nil)
    receive do
      :job_ok -> :ok
    after 1000 ->
        flunk("Job not processed :-S")
    end
  end
end
