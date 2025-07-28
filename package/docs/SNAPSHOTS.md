# BEAM Campus

## ExESDB - The BEAM-native Event Store v0.0.16

### Snapshots

#### Purpose

- Provide a mechanism to store aggregated snapshots.
- Deal with performance bottlenecks for large event streams.

#### Behavior

- `record_snapshot/5`
- `read_snapshot/4`
- `delete_snapshot/4`
- `list_snapshots/3`

#### Implementation

- Supported by `ExESDB.GatewayAPI`
- On-demand, Temporary workers
- Cluster-wide Worker processes using `Swarm`

#### Next Steps

- integrate with `Persistent Subscriptions` for sourcing performance optimization
- automatic snapshots cleanup

#### v0.0.16 Available on

- [Hex](https://hex.pm/packages/ex_esdb)
- [GitHub](https://github.com/beam-campus/ex-esdb)
