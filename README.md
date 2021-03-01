# Roger: RabbitMQ-backed job processing system

[![Build Status](https://github.com/bettyblocks/roger/actions/workflows/elixir/badge.svg)](https://github.com/bettyblocks/roger/actions)
[![Hex pm](http://img.shields.io/hexpm/v/roger.svg?style=flat)](https://hex.pm/packages/roger)
[![Inline docs](http://inch-ci.org/github/bettyblocks/roger.svg)](http://inch-ci.org/github/bettyblocks/roger)

Roger is a multi-tenant, high performance job processing system for Elixir.


## Features

- Multi-tentant architecture, ("partitions")
- Based on RabbitMQ
- Per-queue concurrency control
- Jobs cancellation (both queued and while running)
- Option to enforce per-partition job uniqueness
- Option to enforce job uniqueness during execution
- Pausing / unpausing work queues
- All operations are cluster-aware
- Retry w/ exponential backoff
- Resilient against AMQP network conditions (reconnects, process crashes, etc)
- Partition state persistence between restarts (configurable)
- Detailed queue / partition information
- Graceful shutdown on stopping 

## Getting started

### 1. Check requirements

- Elixir 1.9.0 or greater
- RabbitMQ 3.6.0 or greater

### 2. Install Roger

Edit `mix.exs` and add `roger` to your list of dependencies and applications:

```elixir
def deps do
  [{:roger, "~> 3.0"}]
end
```

Then run `mix deps.get`.

### 3. Basic configuration amqp
```elixir
config :amqp,
  connections: [
    roger_conn: [
      host: "localhost",
      port: 5672
    ]
  ],
  channels: [
    send_channel: [connection: :roger_conn]
  ]
```

### 4. Basic configuration Roger

Configure connection and channel name of amqp.
Also able to set some default queues.

```elixir
config :roger, :partitions,
  example: [default: 10, other: 2],
  connection_name: :roger_conn,
  channel_name: :send_channel
```

### 5. Define Roger job

Use `Roger.Job` module in your job module and define `perform/1` that takes a map as an argument.

```elixir
defmodule TestJob do
  use Roger.Job
  
  @impl true
  def perform(_args) do
    # perform some work here...
  end
end
```

Any exception will cause the job to be retried if the following callback is set.
```elixir 
@impl true
def retryable(), do: true
```


### 6. Enqueueing Roger job

Then enqueue a job

```elixir
{:ok, job} = Roger.Job.create(TestJob, %{"argument": 1})
Roger.Job.enqueue(job, "myapp")

```

## Advanced options

### Graceful shutdown

For graceful shutdown with like phoenix you need to disable auto starting roger and start it in the supervisor tree.

To do that you need to set the following config:

```elixir
config :roger,
  start_on_application: false
```

By default the graceful shutdown wait 10 seconds on the workers but it can be changed by the `shutdown_timeout` setting.

And add the following line to your app supervisor tree at the end because the genservers get shutdown from the last to the first.

```elixir
supervisor(Roger, [])
```
