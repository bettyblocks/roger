defmodule Roger.Partition.GlobalTest do
  use ExUnit.Case
  use Roger.AppCase, queues: [default: 10, fast: 20, expression: 10]

  alias Roger.Partition
  alias Roger.Partition.Global

  test "pause and unpause queues" do
    assert {:ok, %MapSet{}} == Global.queue_get_paused(@app)

    :ok = Global.queue_pause(@app, :default)
    :ok = Global.queue_pause(@app, :fast)
    :ok = Global.queue_pause(@app, :expression)

    {:ok, queues} = Global.queue_get_paused(@app)
    Enum.each queues, fn(q) ->
      :ok = Global.queue_resume(@app, q)
    end

    assert {:ok, %MapSet{}} == Global.queue_get_paused(@app)
  end

  test "(not) alive check" do
    assert {:error, :not_started} == Global.queue_get_paused("foo")
  end

end
