defmodule Roger.Partition.GlobalTest do
  use ExUnit.Case

  alias Roger.Partition
  alias Roger.Partition.Global


  setup do
    {:ok, _pid} = Partition.start("test", [default: 10, fast: 20, expression: 10])
    :ok
  end

  test "pause and unpause queues" do

    assert MapSet.new([]) == Global.queue_get_paused("test")

    :ok = Global.queue_pause("test", :default)
    :ok = Global.queue_pause("test", :fast)
    :ok = Global.queue_pause("test", :expression)

    Enum.each Global.queue_get_paused("test"), fn(q) ->
      :ok = Global.queue_resume("test", q)
    end

    assert MapSet.new([]) == Global.queue_get_paused("test")
  end

end
