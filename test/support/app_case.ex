defmodule Roger.AppCase do
  @moduledoc false
  use ExUnit.CaseTemplate

  using(opts) do
    quote do

      require Logger
      alias Roger.{Application, Queue, Job}

      setup do

        # empty the default queue first
        {:ok, channel} = Roger.AMQPClient.open_channel
        AMQP.Queue.declare(channel, "test-default")
        AMQP.Queue.purge(channel, "test-default")

        Process.register(self(), :testcase)
        app = %Application{id: "test", queues: [Queue.define(:default, 10)]}
        {:ok, _pid} = Application.start(app)

        Elixir.Application.put_env(:roger, :callbacks, unquote(opts)[:callbacks] || [])

        on_exit fn ->
          Elixir.Application.put_env(:roger, :callbacks, [])
        end

        {:ok, %{app: app}}
      end

    end
  end
end
