defmodule Roger.Integration do
  @moduledoc false

  require Logger

  @hostname elem(:inet.gethostname, 1)
  @master :"a@#{@hostname}"
  @slaves ~w(a b c d)a
  @slave_nodes (@slaves |> Enum.map(&(String.to_atom("#{&1}@#{@hostname}"))))

  @job_count 200

  def start do
    create_config()

    @slaves |> Enum.map(&start_node/1)

    Logger.info "Nodes running: #{inspect Node.list}"

    {:ok, _} = Application.ensure_all_started(:roger)
    wait_ready(@slave_nodes)

    for _ <- 1..@job_count do
      enqueue
    end

    :timer.sleep 1000
    :rpc.abcast(@slave_nodes, Roger.Integration.Slave, :done)
    result = receive_all(@slave_nodes, %{})

    # assert that all nodes have executed some jobs
    executed = result
    |> Enum.filter(fn({_, v}) -> v > 0 end)
    |> Enum.into(%{})

    @slave_nodes = Map.keys(executed)

    # Assert that all jobs have executed
    @job_count = result |> Map.values |> Enum.sum

    Logger.info "Job execution result: #{inspect result}"
    Logger.info "Test OK."

  end

  defp wait_ready([]), do: :ok
  defp wait_ready(nodes) do
    receive do
      {:ready, node} ->
        wait_ready(nodes -- [node])
    end
  end

  defp receive_all([], result) do
    result
  end
  defp receive_all(nodes, result) do
    receive do
      {:log, node, msg} ->
        Logger.info "[#{node}] - #{msg}"
        receive_all(nodes, result)
      {:done, node, count} ->
        receive_all(nodes -- [node], Map.put(result, node, count))
    end
  end


  defp start_node(node) do
    paths = for p <- :code.get_path, do: ['-pa ', p, ' ']
    |> List.flatten

    {:ok, _} = :ct_slave.start(node,
      kill_if_fail: true,
      monitor_master: true,
      init_timeout: 10,
      startup_functions: [{Roger.Integration.Slave, :start_link, [self()]}],
      erl_flags: paths ++ ' -config /tmp/sys.config'
    )
  end

  defp create_config do
    Application.start(:mix)
    config = Mix.Config.read!("config/config.exs")
    for {app, kvs} <- config do
      for {k, v} <- kvs do
        Application.put_env(app, k, v)
      end
    end
    sys_config_string = :io_lib.format('~p.~n', [config]) |> List.to_string
    File.write("/tmp/sys.config", sys_config_string)
  end



  def start_single do
    create_config()

    {:ok, _} = Application.ensure_all_started(:roger)
    app = if node() == @master do
      Roger.Application.start("integration", [])
    else
      Roger.Application.start("integration", [default: 100])
    end

    :pong = Node.ping(@master)
    IO.puts "Node.list: #{inspect Node.list}"
  end


  def enqueue_many(n \\ 300_000) do
    for _ <- 1..n, do: enqueue
  end

  def enqueue do
    {:ok, job} = Roger.Job.create(Roger.Integration.Jobs.TestJob, %{foo: "bar"})
    Roger.Job.enqueue(job, "integration")
    job
  end

end
