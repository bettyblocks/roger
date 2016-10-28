defmodule Roger.Job.SystemTest do
  use ExUnit.Case

  alias Roger.System

  test "cross-cluster RPC call" do
    assert {:ok, replies} = System.call(:ping)
    assert [{node(), :pong}] == replies
  end

  test "cross-cluster broadcast" do
    assert :ok = System.cast(:ping)
    :timer.sleep 100
  end

end
