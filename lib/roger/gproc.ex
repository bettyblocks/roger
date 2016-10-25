defmodule Roger.GProc do

  @scope :l

  def name(proc), do: {:n, @scope, proc}

  def reg(proc), do: :gproc.reg(name(proc))

  def unreg(proc), do: :gproc.unreg(name(proc))

  def regp(proc), do: :gproc.reg(prop(proc))

  def regp(proc, value), do: :gproc.reg(prop(proc), value)

  def unregp(proc), do: :gproc.unreg(prop(proc))

  def prop(proc), do: {:p, @scope, proc}

  def whereis(proc) do
    map_nil(:gproc.whereis_name(name(proc)))
  end

  def is_alive(proc), do: is_pid(whereis(proc)) and Process.alive?(whereis(proc))

  def via(proc), do: {:via, :gproc, name(proc)}

  defp map_nil(:undefined), do: nil
  defp map_nil(value), do: value

  @doc """
  Return list of {pid, value} pairs for the given selector.
  """
  def find_properties(selector) do
    for [_, pid, value] <- :gproc.select([{{ {:p, @scope, selector}, :_, :_}, [], [:'$$']}]), do: {pid, value}
  end
end
