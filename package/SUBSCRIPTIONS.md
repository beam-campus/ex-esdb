# Subscriptions Mechanism

## The Subscriptions Process

- Subscriptions are based on actions that are performed on the event store.
- Khepri supports Trigger functions to be defined in the store.
- Such Triggers are guarded by a Event filter.
- At this moment, Khepri only supports triggers at the level of Path changes (create, update, delete).

-- GIVEN: a Khepri Store
-- WHEN: a Subscription is registered
-- THEN:
--- an `EmitterGroup` is created, that will spawn a number of `EmitterWorker` processes.

---
