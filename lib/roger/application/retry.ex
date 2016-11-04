defmodule Roger.Application.Retry do
  @moduledoc """

  Retry logic
  """

  alias Roger.{Queue, Job}

  @levels [1, 3, 5, 10, 20, 35, 60, 100, 200, 400, 1000, 1800]

  if Mix.env == :test do
    @one_second 1
  else
    @one_second 1000
  end

  @doc """
  Given an AMQP channel and the application, queues the given job for retry.
  """
  def retry(channel, application, job) do

    {queue, expiration} = setup_retry_queue(channel, application, job)

    payload = Job.encode(%Job{job | retry_count: job.retry_count + 1})
    opts_extra = case expiration do
                   :buried -> []
                   _ -> [expiration: Integer.to_string(expiration)]
                 end
    AMQP.Basic.publish(channel, "", queue, payload, Job.publish_opts(job, application) ++ opts_extra)
    {:ok, expiration}
  end

  defp setup_retry_queue(channel, application, job) do
    queue_type = Job.queue_type(job)
    expiration = if job.retry_count <= Enum.count(@levels) do
      :lists.nth(job.retry_count + 1, @levels)
    else
      :buried
    end

    arguments = [
      {"x-dead-letter-exchange", ""},
      {"x-dead-letter-routing-key", Queue.make_name(application, queue_type)}
    ]
    {queue_name, arguments} = if expiration == :buried do
      {Queue.make_name(application, queue_type, ".buried"), arguments}
    else
      {Queue.make_name(application, queue_type, ".retry.#{expiration}"), arguments ++ [{"x-expires", expiration + 2000}]}
    end

    {:ok, _stats} = AMQP.Queue.declare(channel, queue_name, arguments: arguments)
    {queue_name, expiration}
  end

end
