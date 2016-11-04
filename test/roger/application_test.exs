defmodule Roger.ApplicationTest do
  use ExUnit.Case
  doctest Roger.Application

  alias Roger.{Application, Queue}

  setup do
    Elixir.Application.put_env(:roger, :callbacks, application: TestApplications)
    :ok
  end

  test "start application" do
    app = %Application{id: "test", queues: [Queue.define(:default, 10)]}
    {:ok, _} = Application.start(app)
  end

  test "start application is re-entrant" do
    app = %Application{id: "test", queues: [Queue.define(:default, 10)]}
    {:ok, pid} = Application.start(app)
    {:ok, ^pid} = Application.start(app)
  end

end
