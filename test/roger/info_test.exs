defmodule Roger.Application.InfoTest do
  use ExUnit.Case
  use Roger.AppCase

  alias Roger.Info

  test "get roger info over the entire cluster" do
    node = node()
    assert [{^node, _}] = Info.applications
    assert [{^node, _}] = Info.running_applications
    assert [{^node, _}] = Info.waiting_applications
    assert [{^node, _}] = Info.running_jobs
  end

end
