defmodule Roger.Partition.InfoTest do
  use ExUnit.Case
  use Roger.AppCase

  alias Roger.Info

  test "get roger info over the entire cluster" do
    node = node()
    assert [{^node, _}] = Info.partitions
    assert [{^node, _}] = Info.running_partitions
    assert [{^node, _}] = Info.waiting_partitions
    assert [{^node, _}] = Info.running_jobs
  end

end
