defmodule Roger.Application.Retry do
  @moduledoc """

  Retry logic
  """

  alias Roger.{Queue, Job}

  @levels [1, 3, 5, 10, 20, 35, 60, 100, 200, 400, 1000, 1800]
  @levels_by_prio Enum.zip(Enum.count(@levels)..1, @levels) |> Enum.into(%{})
  if Mix.env == :test do
    @one_second 1
  else
    @one_second 1000
  end

  def retry(channel, application, job) do
    queue_type = Job.queue_type(job)
    declare_retry_queue(channel, application, queue_type)

    prio = Enum.count(@levels) - job.retry_count
    job = %{job | retry_count: job.retry_count + 1}

    opts = [
      content_type: "application/json",
      persistent: true,
      message_id: job.id,
      app_id: application.id,
    ]

    payload = Poison.encode!(job)
    case prio > 0 do
      true ->
        queue = Queue.make_name(application, queue_type, ".retry")
        opts = [priority: prio, expiration: Integer.to_string(@levels_by_prio[prio] * @one_second)] ++ opts
        AMQP.Basic.publish(channel, "", queue, payload, opts)
        {:ok, :queued}
      false ->
        queue = Queue.make_name(application, queue_type, ".buried")
        AMQP.Basic.publish(channel, "", queue, payload, opts)
        {:ok, :buried}
    end
  end

  defp declare_retry_queue(channel, application, type) do
    arguments = [
      {"x-expires", Enum.max(@levels) * 1000},
      {"x-max-priority", Enum.count(@levels)},
      {"x-dead-letter-exchange", ""},
      {"x-dead-letter-routing-key", Queue.make_name(application, type)}
    ]
    queue_name = Queue.make_name(application, type, ".retry")
    {:ok, _stats} = AMQP.Queue.declare(channel, queue_name, arguments: arguments)
    queue_name = Queue.make_name(application, type, ".buried")
    {:ok, _stats} = AMQP.Queue.declare(channel, queue_name)

  end
end
