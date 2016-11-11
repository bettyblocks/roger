# Overview

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

This starts `myapp` with two queues, one with maximum 10 concurrent
workers, and one with 5. As soon as you've done this, and the
partition is running, you can open the RabbitMQ management console
at http://localhost:15672/#/queues to verify that there indeed are two
queues, named `myapp-default` and `myapp-other`.

When you click on one of the queues, you'll see that it has one
consumer attached to it. You could start a second Elixir node
(clustered with the first) now and see that there are now two
consumers on each queue. The consumer's "prefetch count" field
corresponds to the concurrency level of the queue.
