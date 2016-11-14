defmodule Roger.WorkerTest do
  use ExUnit.Case
  #doctest Roger.Worker

  alias Roger.{Partition, Partition.WorkerSupervisor, Job}

  @app "test"

  setup do
    Process.register(self(), Roger.WorkerTest)
    {:ok, _pid} = Partition.start(@app, [default: 10])
    :ok
  end


  defmodule TestJob do
    use Roger.Job

    def perform([]) do
      send(Roger.WorkerTest, :job_ok)
    end

  end

  @payload :erlang.term_to_binary(%Job{id: "asdf", module: TestJob, args: []})
  #@payload ~s({"id": "123", "module": "Elixir.Roger.WorkerTest.TestJob", "args": []})

  test "start worker in partition worker supervisor" do
    {:ok, _pid} = WorkerSupervisor.start_child(@app, :channel, @payload, nil)
    receive do
      :job_ok -> :ok
    after 1000 ->
        flunk("Job not processed :-S")
    end
  end
end
