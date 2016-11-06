# Roger: Multi-tenant, high performance job processing system

[![Build Status](https://travis-ci.org/bettyblocks/roger.png?branch=master)](https://travis-ci.org/bettyblocks/roger)


**TODO: Add description**

## Feature checklist

- [x] Multi-tentant architecture
- [x] Based on Rabbitmq
- [x] Per-queue concurrency control
- [x] Jobs cancellation (both in the queue and while running)
- [x] Option to enforce per-application job uniqueness
- [x] Option to enforce job uniqueness during execution
- [x] Pausing / unpausing work queues
- [x] All operations are cluster-aware
- [x] Retry w/ exponential backoff
- [ ] Resilient against AMQP network conditions (reconnects, process crashes, etc)
- [ ] Application state persistence between restarts (callback based? mnesia?)
- [ ] Management API (phoenix mountable); return info from each node
- [ ] Documentation


## Configuration

To provide process isolation and fair scheduling, Roger groups its
work queues by what are called *Roger applications*. Each Roger
application can have zero or more queues associated with it, with a
separate concurrency level per queue.

By default, when the `:roger` OTP application starts, it does not have
any applications running. To always start a certain application when
Roger starts, do the following in `config.exs`:

    config :roger, :applications,
      myapp: [default: 10, other: 5]

This starts `myapp` with two queues, one with maximum 10 concurrent
workers, and one with 5. As soon as you've done this, and the
application is running, you can open the RabbitMQ management console
at http://localhost:15672/#/queues to verify that there indeed are two
queues, named `myapp-default` and `myapp-other`.

When you click on one of the queues, you'll see that it has one
consumer attached to it. You could start a second Elixir node
(clustered with the first) now and see that there are now two
consumers on each queue. The consumer's "prefetch count" field
corresponds to the concurrency level of the queue.

### Callback modules

Roger can be configured with callback modules which invoke functions
on various places in the application's life cycle.

    config :roger, :callbacks,
      worker: MyWorkerModule

In this scenario, `MyWorkerModule` needs to *use* `Roger.Worker.Callback`:

    defmodule MyWorkerModule do
      use Roger.Worker.Callback
    end

In this worker module, you can implement the functions `before_run/2`,
`after_run/2`, `on_error/4`, `on_cancel/2` and `on_buried/2` to
respond to job events.
