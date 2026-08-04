defmodule Roger.AppCase do
  @moduledoc false
  use ExUnit.CaseTemplate

  @doc """
  Block until Roger's system channels are up.

  Some tests drop the AMQP connection on purpose, and both `Roger.System`
  and `Roger.ApplySystem` need a moment to redeclare their queues
  afterwards. Commands cast over those channels are silently dropped
  while they are down, which would make the next test fail for reasons
  that have nothing to do with what it is testing.
  """
  def await_connected(tries \\ 200) do
    cond do
      connected?(Roger.System) and connected?(Roger.ApplySystem) ->
        :ok

      tries == 0 ->
        {:error, :not_connected}

      true ->
        :timer.sleep(25)
        await_connected(tries - 1)
    end
  end

  defp connected?(mod) do
    mod.connected?()
  catch
    :exit, _reason -> false
  end

  using(opts) do
    queues = opts[:queues] || [default: 10]

    quote do
      @app "test"

      require Logger
      alias Roger.{Partition, Queue, Job}

      setup do
        Process.register(self(), unquote(__CALLER__.module))
        :ok = Roger.AppCase.await_connected()
        {:ok, _pid} = Partition.start(@app, unquote(queues))

        Application.put_env(:roger, :callbacks, unquote(opts)[:callbacks] || nil)

        on_exit(fn ->
          partition_info =
            try do
              Roger.NodeInfo.running_partitions()
            catch
              _, _ ->
                %{}
            end

          Roger.Partition.stop(@app)
          # Clean up all queues
          channel_name = Application.get_env(:roger, :channel_name)
          {:ok, channel} = AMQP.Application.get_channel(channel_name)

          for {id, queues} <- partition_info, {q, _} <- queues do
            queue = Roger.Queue.make_name(id, q)
            {:ok, _} = AMQP.Queue.delete(channel, queue)
          end

          # Remove all roger env. variables except AMQP connection info
          for {key, _} <- Application.get_all_env(:roger), key not in [:channel_name, :connection_name] do
            Application.delete_env(:roger, key)
          end
        end)

        :ok
      end
    end
  end
end
