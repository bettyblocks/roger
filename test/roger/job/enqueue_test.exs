defmodule Roger.Job.EnqueueTest do
  use ExUnit.Case
  use Roger.AppCase

  alias Roger.Job

  alias Roger.{Application, Queue}


  defmodule MyCalculation do
    use Roger.Job

    def perform([num]) do
      send(:testcase, num * num)
    end

  end

  test "job enqueue", %{app: app} do
    {:ok, job} = Job.create(MyCalculation, [2])
    :ok = Job.enqueue(job, app)

    receive do
      4 ->
        :ok

    after 1000 ->
        flunk("Job not executed")
    end
  end

end
