defmodule Roger.Partition.Global.AliveCheck do
  @moduledoc """
  Decorator function which checks whether the partition has been started first
  """

  use Decorator.Define, [alive_check: 0]

  def alive_check(body, %{args: [partition_id | _args]} = _context) do
    quote do
      pid = GenServer.whereis(Roger.Partition.Global.global_name(unquote(partition_id)))
      case is_pid(pid) and Process.alive?(pid) do
        true ->
          case unquote(body) do
            :ok -> :ok
            true -> true
            false -> false
            result -> {:ok, result}
          end
        false -> {:error, :not_started}
      end
    end
  end

end
