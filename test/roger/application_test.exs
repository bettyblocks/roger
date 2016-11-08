defmodule Roger.ApplicationTest do
  use ExUnit.Case

  alias Roger.{NodeInfo, Application, ApplicationSupervisor}

  test "start and stop application through the registry" do

    {:ok, _pid} = Application.start("test", [default: 10])

    assert has_test_app(NodeInfo.running_applications)

    :ok = Application.stop("test")
    :timer.sleep 50

    assert !has_test_app(NodeInfo.running_applications)
  end

  test "automatic restart after supervisor stop" do

    {:ok, pid} = Application.start("test", [default: 10])

    :ok = ApplicationSupervisor.stop_child(pid)
    :timer.sleep 50


    assert !has_test_app(NodeInfo.running_applications)
    assert has_test_app(NodeInfo.waiting_applications)

    :timer.sleep 1000
    # it restarts

    assert has_test_app(NodeInfo.running_applications)
    assert !has_test_app(NodeInfo.waiting_applications)

  end

  defp has_test_app(apps) do
    apps["test"] != nil
  end

end
