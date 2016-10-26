# Roger: Multi-tenant job processor

[![Build Status](https://travis-ci.org/arjan/decorator.png?branch=master)](https://travis-ci.org/bettyblocks/roger)


**TODO: Add description**

## Feature checklist

- [x] Multi-tentant architecture
- [x] based on Rabbitmq
- [x] per-queue concurrency control
- [x] jobs cancellation (both in the queue and while running)
- [x] option to enforce per-application job uniqueness
- [ ] option to enforce job uniqueness during execution
- [ ] all operations are cluster-aware
- [ ] pausing / unpausing work queues
- [ ] retry w/ exponential backoff
- [ ] Management API (phoenix mountable); return info from each node (rabbitmq pubsub?)
- [ ] Documentation


## Configuration

Roger can be configured with callback modules which invoke functions
on various places in the application's life cycle.
