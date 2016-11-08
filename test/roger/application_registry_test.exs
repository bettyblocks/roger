defmodule Roger.ApplicationRegistryTest do
  use ExUnit.Case

  alias Roger.{ApplicationRegistry, Application, Queue, ApplicationSupervisor}

  test "start and stop application through the registry" do

    assert !has_test_app(ApplicationRegistry.running_applications)

    app = %Application{id: "test", queues: [Queue.define(:default, 10)]}
    {:ok, _pid} = ApplicationRegistry.start(app)

    assert has_test_app(ApplicationRegistry.running_applications)

    :ok = ApplicationRegistry.stop(app)
    :timer.sleep 50

    assert !has_test_app(ApplicationRegistry.running_applications)

  end

  test "automatic restart after supervisor stop" do

    assert !has_test_app(ApplicationRegistry.running_applications)

    app = %Application{id: "test", queues: [Queue.define(:default, 10)]}
    {:ok, pid} = ApplicationRegistry.start(app)

    :ok = ApplicationSupervisor.stop_child(pid)
    :timer.sleep 50


    assert !has_test_app(ApplicationRegistry.running_applications)
    assert has_test_app(ApplicationRegistry.waiting_applications)

    :timer.sleep 1000
    # it restarts

    assert has_test_app(ApplicationRegistry.running_applications)
    assert !has_test_app(ApplicationRegistry.waiting_applications)

  end

  defp has_test_app(apps) do
    Enum.filter(apps, &(&1.id == "test")) |> Enum.count > 0
  end

end
