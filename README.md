# Roger: Multi-tenant job processor

[![Build Status](https://travis-ci.org/arjan/decorator.png?branch=master)](https://travis-ci.org/bettyblocks/roger)
[![Hex pm](http://img.shields.io/hexpm/v/decorator.svg?style=flat)](https://hex.pm/packages/roger)


**TODO: Add description**

## Feature checklist

- [x] Multi-tentant architecture
- [x] based on Rabbitmq
- [x] per-queue concurrency control
- [x] jobs cancellation (both in the queue and while running)
- [ ] all operations are cluster-aware
- [ ] enforce job uniqueness during execution
- [ ] enforce job uniqueness per queue
- [ ] pausing / unpausing work queues
- [ ] retry w/ exponential backoff
- [ ] Management API (phoenix mountable); return info from each node (rabbitmq pubsub?)
- [ ] Documentation


## Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be installed as:

  1. Add `roger` to your list of dependencies in `mix.exs`:

    ```elixir
    def deps do
      [{:roger, "~> 0.1.0"}]
    end
    ```

  2. Ensure `roger` is started before your application:

    ```elixir
    def application do
      [applications: [:roger]]
    end
    ```
