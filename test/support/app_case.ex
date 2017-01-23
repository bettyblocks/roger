defmodule Roger.AppCase do
  @moduledoc false
  use ExUnit.CaseTemplate

  using(opts) do

    queues = opts[:queues] || [default: 10]
    quote do

      @app "test#{unquote(:erlang.monotonic_time)}"

      require Logger
      alias Roger.{Partition, Queue, Job}

      setup do
        Process.register(self(), unquote(__CALLER__.module))
        {:ok, _pid} = Partition.start(@app, unquote(queues))

        Application.put_env(:roger, Roger.Partition.Worker, callbacks: (unquote(opts)[:callbacks] || nil))

        on_exit fn ->
          :ok = Roger.Partition.stop(@app)
          Application.put_env(:roger, Roger.Partition.Worker, [])
        end

        :ok
      end

    end
  end
end
