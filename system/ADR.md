# Architecture Decision Records

## 2025.05.24

### Emitter pools must run on the Ra leader.

Given that Khepri triggers are executed on the Ra leader, emitter pools must run on the Ra leader.
In order to achieve this, it is necessary that a separate process existst, that monitors the Cluster and subscribes to Ra's leadership changes, by starting relevant emitter pools on the new leader.

## 2025.05.02

### Triggers will obtain Emitter Pids from :pg (Process Groups)

Experimentation with :khepri's trigger model has shown that it is advised to use as few dependencies as possible, when defining the trigger functions. This is because :khepri uses :horus to decompile such functions and build a separate module. For this reason, we limit the dependencies for these trigger functions to :pg (Process Groups), which is an :erlang native module that allows for inter-process communication.

## 2025.04.16

### Subscriptions will be managed via a registry.

`subscribe_to` and `unsubscribe` will interact with the :subscriptions branch of the store, but instead of storing the pid of the subscriber, the subscriber will be stored in a registry.

## 2025.04.13

### Each Store will contain separate branches for Streams, Subscriptions, and Projections

- `:streams` will be used to store the events that are being read from and written to the store.
- `:subscriptions` will be used to store the subscription information of so-called `Persistent Subscriptions`.
- `:projections` can best be thought of as stored procedures that are used to transform the events in the `Streams` into a different format or to enrich the streams with secondary or derived events, to name a few possible use cases.

Thus:

```mono
:khepri
  |
  +-:manage_orders
      |
      +-:streams
      |
      +-:subscriptions
      |
      +-:projections
```
