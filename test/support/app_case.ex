defmodule Roger.AppCase do
  @moduledoc false
  use ExUnit.CaseTemplate

  using(opts) do
    queues = opts[:queues] || [default: 10]

    quote do
      @app "test"

      require Logger
      alias Roger.{Partition, Queue, Job}

      setup do
        Process.register(self(), unquote(__CALLER__.module))
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
          {:ok, channel} = AMQP.Application.get_channel(:send_channel)

          for {id, queues} <- partition_info, {q, _} <- queues do
            queue = Roger.Queue.make_name(id, q)
            {:ok, _} = AMQP.Queue.delete(channel, queue)
          end

          # Remove all roger env. variables except AMQP connection info
          for {key, _} <- Application.get_all_env(:roger), key != :amqp do
            Application.delete_env(:roger, key)
          end
        end)

        :ok
      end
    end
  end
end
