defmodule Roger.JobTest do
  use ExUnit.Case

  doctest Roger.Job

  alias Roger.Job

  defmodule SquareJob do
    use Roger.Job

    def perform([num]) do
      num * num
    end

  end


  test "job create" do
    {:ok, job} = Job.create(SquareJob, [2])
    assert is_atom(job.module)
    assert is_list(job.args)
    assert is_binary(job.id)
  end


  defmodule QueueKeyJob do
    use Roger.Job

    def perform([num]) do
      num * num
    end

    def queue_key([num]) do
      "num-#{num}"
    end

  end


  test "job create with queue key" do
    {:ok, job} = Job.create(QueueKeyJob, [2])
    assert is_atom(job.module)
    assert is_list(job.args)
    assert is_binary(job.id)
    assert "num-2" == job.queue_key
  end

  @payload :erlang.term_to_binary(%Job{id: "asdf", module: SquareJob, args: [2]})

  test "job deserialization from binary" do
    {:ok, job} = Job.decode(@payload)

    assert SquareJob == job.module
    assert [2] == job.args
    assert "asdf" == job.id
    assert nil == job.queue_key
    assert nil == job.execution_key
  end

  test "job execute OK" do
    {:ok, job} = Job.create(SquareJob, [2])
    assert 4 == Job.execute(job)
  end

  test "invalid decoded job, no id" do
    payload = :erlang.term_to_binary(%Job{})
    {:error, msg} = Job.decode(payload)
    assert Regex.match? ~r/Job id must be set/, msg
  end

  test "invalid decoded job, unknown module" do
    payload = :erlang.term_to_binary(%Job{id: "asdf", module: "NoExisting"})
    {:error, msg} = Job.decode(payload)
    assert Regex.match? ~r/Job module must be an atom/, msg
  end

end
