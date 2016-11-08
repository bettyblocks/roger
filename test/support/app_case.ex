defmodule Roger.AppCase do
  @moduledoc false
  use ExUnit.CaseTemplate

  using(opts) do
    quote do

      @app "test"

      require Logger
      alias Roger.{Application, Queue, Job}

      setup do

        Process.register(self(), :testcase)
        {:ok, _pid} = Application.start(@app, default: 10)

        Elixir.Application.put_env(:roger, :callbacks, unquote(opts)[:callbacks] || [])

        on_exit fn ->
          Elixir.Application.put_env(:roger, :callbacks, [])
        end

        :ok
      end

    end
  end
end
