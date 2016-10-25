defmodule Roger.ApplicationTest do
  use ExUnit.Case
  doctest Roger.Application

  alias Roger.{Application, Queue}

  defmodule TestApplications do
    use Roger.Application.Callback

    def defined_applications do
      [%Application{id: :test}]
    end
  end

  setup do
    Elixir.Application.put_env(:roger, :callbacks, application: TestApplications)
    :ok
  end

  test "list applications" do
    assert [app] = Application.defined_applications
    assert :test == app.id
  end

  test "start application" do
    app = %Application{id: "test", queues: [Queue.define(:default, 10)]}
    {:ok, _} = Application.start(app)

    # Check whether application consumer is alive
    assert Roger.Application.Consumer.is_alive?(app)
    :timer.sleep(100)
  end

  test "start application is re-entrant" do
    app = %Application{id: "test", queues: [Queue.define(:default, 10)]}
    {:ok, pid} = Application.start(app)
    {:ok, ^pid} = Application.start(app)
  end

end
