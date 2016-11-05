defmodule Roger.Job.CancelTest do
  use ExUnit.Case
  use Roger.AppCase, callbacks: [worker: Roger.Job.CancelTest.CancelCallbacks]

  alias Roger.Job

  alias Roger.{Application, Queue, Application.Global}

  defmodule CancelCallbacks do
    use Roger.Application.Worker.Callback

    def on_cancel(_app, job) do
      send(:testcase, {:cancel, job.id})
    end

  end

  defmodule MyJob do
    use Roger.Job
    def perform(_), do: nil
  end


  test "statemanager cancel logic", %{app: app} do
    {:ok, job} = Job.create(MyJob, [2])

    assert :ok = Global.cancel_job(app, job.id)

    # When calling is_cancelled, state is not touched
    assert true == Global.cancelled?(app, job.id)
    assert true == Global.cancelled?(app, job.id)

    # When called with :remove option, the id is removed from the
    # cancel set
    assert true == Global.cancelled?(app, job.id, :remove)
    assert false == Global.cancelled?(app, job.id, :remove)

  end


  test "it can cancel a job that's in the queue", %{app: app} do
    {:ok, job} = Job.create(MyJob, [2])
    :ok = Job.enqueue(job, app)
    assert :ok = Global.cancel_job(app, job.id)

    receive do
      {:cancel, id} ->
        assert id == job.id
    after 1000 ->
        flunk("Enqueued job not cancelled.")
    end
  end



  defmodule MyCancellableJob do
    use Roger.Job

    def perform(_) do
      send(:testcase, :job_running)
      :timer.sleep(200)
    end
  end

  test "it can cancel a job that's running", %{app: app} do

    # Create and enqueue a job
    {:ok, job} = Job.create(MyCancellableJob, [2])
    :ok = Job.enqueue(job, app)
    # Wait until it says it's running
    receive do
      :job_running -> :ok
    after 1000 ->
        flunk("Job did not start")
    end

    # Now cancel it
    assert :ok = Global.cancel_job(app, job.id)

    # Wait until the on_cancel callback fires
    receive do
      {:cancel, id} ->
        assert id == job.id
    after 1000 ->
        flunk("Running job not cancelled.")
    end

  end

end
