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
- [x] Resilient against AMQP network conditions (reconnects, process crashes, etc)
- [x] Application state persistence between restarts (configurable)
- [x] Detailed queue / application information
- [ ] Documentation
