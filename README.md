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
