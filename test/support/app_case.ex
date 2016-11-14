defmodule Roger.AppCase do
  @moduledoc false
  use ExUnit.CaseTemplate

  using(opts) do
    quote do

      @app "test"

      require Logger
      alias Roger.{Partition, Queue, Job}

      setup do

        Process.register(self(), unquote(__CALLER__.module))
        {:ok, _pid} = Partition.start(@app, default: 10)

        Application.put_env(:roger, Roger.Partition.Worker, callbacks: (unquote(opts)[:callbacks] || nil))

        on_exit fn ->
          Application.put_env(:roger, Roger.Partition.Worker, [])
        end

        :ok
      end

    end
  end
end
