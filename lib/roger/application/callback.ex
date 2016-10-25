defmodule Roger.Application.Callback do

  defmacro __using__(_) do
    quote do
      @behaviour unquote(__MODULE__)

      def defined_applications(), do: []

      defoverridable defined_applications: 0

    end
  end

  @callback defined_applications() :: [Roger.Application.t]

end
