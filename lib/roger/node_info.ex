defmodule Roger.NodeInfo do
  @moduledoc """
  Get information about the current node's jobs and queues.
  """

  alias Roger.{Application, Application.Consumer, GProc, AMQPClient, Job}

  @doc """
  Retrieve combined application info on all running and waiting applications.
  """
  def applications() do
    %{waiting: waiting_applications(),
      running: running_applications()}
  end

  @doc """
  Retrieve all applications that are currently started on this node.
  """
  def running_applications() do
    for {:app_supervisor, id} <- Roger.GProc.find_names({:app_supervisor, :_}) do
      {id, Consumer.get_queues(id)}
    end
    |> Enum.into(%{})
  end

  @doc """
  Retrieve all applications that are currently waiting for start.

  When an application is waiting for start, it typically means that
  the application had trouble starting (e.g. due to a failed AMQP
  connection). When this is the case, the application will be kept in
  the ApplicationRegistry and retried regularly.
  """
  def waiting_applications() do
    GenServer.call(Application, :waiting_applications)
  end


  @doc """
  Retrieve all jobs that are currently running on this node.
  """
  def running_jobs() do
    running_applications()
    |> Enum.map(fn({id, _queues}) ->
      {id, running_jobs(id)}
    end)
    |> Enum.into(%{})
  end

  @doc """
  Retrieve all running jobs for the given application on this node.
  """
  def running_jobs(app_id) do
    selector = {:roger_job_worker_meta, app_id, :_}
    for {_pid, job} <- GProc.find_properties(selector) do
      job
    end
  end

  @doc """
  Retrieve queued jobs for the given application.

  This basically does a `basic.get` AMQP command on the queue and
  requeues the message using a nack.
  """
  def queued_jobs(app_id, queue_type, count \\ 100) do
    {:ok, channel} = AMQPClient.open_channel()

    queue = Roger.Queue.make_name(app_id, queue_type)
    result = get_queue_messages(channel, queue, count)

    :ok = AMQP.Channel.close(channel)
    result
  end

  defp get_queue_messages(channel, queue, count) do
    get_queue_messages(channel, queue, count, [])
  end

  defp get_queue_messages(_, _, 0, result) do
    result
  end
  defp get_queue_messages(channel, queue, count, acc) do
    case AMQP.Basic.get(channel, queue, no_ack: false) do
      {:ok, payload, _meta} ->
        {:ok, job} = Job.decode(payload)
        get_queue_messages(channel, queue, count - 1, [job | acc])
      {:empty, _} ->
        acc
    end
  end

end
