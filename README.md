# Roger: RabbitMQ-backed job processing system

[![Build Status](https://travis-ci.org/bettyblocks/roger.png?branch=master)](https://travis-ci.org/bettyblocks/roger)
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

## Getting started

### 1. Check requirements

- Elixir 1.4 or greater
- RabbitMQ 3.6.0 or greater

### 2. Install Roger

Edit `mix.exs` and add `roger` to your list of dependencies and applications:

```elixir
def deps do
  [{:roger, "~> 1.2"}]
end
```

Then run `mix deps.get`.

### 3. Basic configuration Roger

Configure hosts and default queues:

```elixir
config :roger, Roger.AMQPClient,
  host: "localhost",
  port: 5672

config :roger, :partitions,
  example: [default: 10, other: 2]
```

### 4. Define Roger job

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


### 5. Enqueueing Roger job

Then enqueue a job

```elixir
{:ok, job} = Roger.Job.create(TestJob, %{"argument": 1})
Roger.Job.enqueue(job, "myapp")

```

