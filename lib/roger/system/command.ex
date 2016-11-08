defmodule Roger.System.Command do
  @moduledoc false

  def new(command, args \\ nil) do
    {command, args}
  end

  def encode(struct), do: :erlang.term_to_binary(struct)
  def decode(struct), do: :erlang.binary_to_term(struct)

end
