# Overview

Roger manages job queues in *partitions*. each partition contains one
or more *queues*. The unit of work is a *job*; defined by a module
which implements `Roger.Job`. Jobs are enqueued into a queue, and
picked up by the partition's consumer, which spawns a supervised
process, the *worker* (`Roger.Partition.Worker`). This worker then
calls the `perform/1` function on the job's module.

## Jobs

Jobs are Elixir module which implement `Roger.Job`:

    defmodule TestJob do
      use Roger.Job
      def perform(_args) do
        # perform some work here...
      end
    end

The module has one required callback function, `perform/1`, which gets
called to do the job's work. To execute the job, it needs to be
created and then enqueued in a partition:

    {:ok, job} = Roger.Job.create(TestJob, %{"argument": 1})
    Roger.Job.enqueue(job, "myapp")

By default, a job gets executed on the queue named `default`. This
example also assumes the "myapp" partition exists. See below on how to
define a partition.

On more information on a job's properties, see the `Roger.Job` module.


## Partitions

To provide process isolation and fair scheduling, Roger groups its
work queues by what are called *partitions*. Each partition can have
zero or more queues associated with it, with a separate concurrency
level per queue.

By default, when the `:roger` OTP partition starts, it does not have
any partitions running. To always start a certain partition when
Roger starts, do the following in `config.exs`:

    config :roger, :partitions,
      myapp: [default: 10, other: 5]

To start a partition at runtime, run:

    Roger.Partition.start("myapp", [default: 10, other: 5])

This starts `myapp` with two queues, one with maximum 10 concurrent
workers, and one with 5. As soon as you've done this, and the
partition is running, you can open
the [RabbitMQ management console](http://localhost:15672/#/queues) to
verify that there indeed are two queues, named `myapp-default` and
`myapp-other`.

In this web interface, when you click on one of the queues, you'll see
that it has one consumer attached to it. You could start a second
Elixir node (clustered with the first) now and see that there are now
two consumers on each queue. The consumer's "prefetch count" field
corresponds to the concurrency level of the queue.
