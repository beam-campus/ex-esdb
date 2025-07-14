defmodule ExESDB.Themes do
  @moduledoc false
  alias BCUtils.ColorFuncs, as: CF

  def app(pid, msg),
    do: "[#{CF.black_on_blue()}#{inspect(pid)}#{CF.reset()}] [ExESDB Server] #{msg}"

  def system(pid, msg),
    do: "[#{CF.black_on_magenta()}#{inspect(pid)}#{CF.reset()}] [ExESDB Main System] #{msg}"

  def core_system(pid, msg),
    do: "[#{CF.black_on_magenta()}#{inspect(pid)}#{CF.reset()}] [CoreSystem] #{msg}"

  def notification_system(pid, msg),
    do: "[#{CF.black_on_cyan()}#{inspect(pid)}#{CF.reset()}] [NotificationSystem] #{msg}"

  def store(pid, msg),
    do: "[#{CF.black_on_green()}#{inspect(pid)}#{CF.reset()}] [Store] #{msg}"

  def cluster(pid, msg),
    do: "[#{CF.yellow_on_blue()}#{inspect(pid)}#{CF.reset()}] [Cluster] #{msg}"

  def store_cluster(pid, msg),
    do: "[#{CF.yellow_on_black()}#{inspect(pid)}#{CF.reset()}] [StoreCluster] #{msg}"

  def store_coordinator(pid, msg),
    do: "[#{CF.white_on_blue()}#{inspect(pid)}#{CF.reset()}] [StoreCoordinator] #{msg}"

  def store_registry(pid, msg),
    do: "[#{CF.white_on_blue()}#{inspect(pid)}#{CF.reset()}] [StoreRegistry] #{msg}"

  def cluster_system(pid, msg),
    do: "[#{CF.bright_white_on_blue()}#{inspect(pid)}#{CF.reset()}] [ClusterSystem] #{msg}"

  def node_monitor(pid, msg),
    do: "[#{CF.yellow_on_magenta()}#{inspect(pid)}#{CF.reset()}] [NodeMonitor] #{msg}"

  def projector(pid, msg),
    do: "[#{CF.black_on_white()}#{inspect(pid)}#{CF.reset()}] [Projector] #{msg}"

  def monitor(pid, msg),
    do: "[#{CF.yellow_on_magenta()}#{inspect(pid)}#{CF.reset()}] [Monitor] #{msg}"

  def emitter_pool(pid, msg),
    do: "[#{CF.yellow_on_black()}#{inspect(pid)}#{CF.reset()}] [EmitterPool] #{msg}"

  def emitter_worker(pid, msg),
    do: "[#{CF.yellow_on_black()}#{inspect(pid)}#{CF.reset()}] [Emitter] #{msg}"

  def persistent_emitter_worker(pid, msg),
    do: "[#{CF.yellow_on_black()}#{inspect(pid)}#{CF.reset()}] [PersistentEmitter] #{msg}"

  def pubsub(pid, msg),
    do: "[#{CF.black_on_cyan()}#{inspect(pid)}#{CF.reset()}] [PubSub] #{msg}"

  ############ LEADER SYSTEM ##############
  def leader_system(pid, msg),
    do: "[#{CF.black_on_magenta()}#{inspect(pid)}#{CF.reset()}] [LeaderSystem] #{msg}"

  def leader_worker(pid, msg),
    do: "[#{CF.black_on_magenta()}#{inspect(pid)}#{CF.reset()}] [LeaderWorker] #{msg}"

  def leader_tracker(pid, msg),
    do: "[#{CF.black_on_magenta()}#{inspect(pid)}#{CF.reset()}] [LeaderTracker] #{msg}"

  ######## SUBSCRIPTIONS ############
  def subscriptions(pid, msg),
    do: "[#{CF.black_on_white()}#{inspect(pid)}#{CF.reset()}] [Subscriptions] #{msg}"

  def subscriptions_reader(pid, msg),
    do: "[#{CF.black_on_white()}#{inspect(pid)}#{CF.reset()}] [SubscriptionsReader] #{msg}"

  def subscriptions_writer(pid, msg),
    do: "[#{CF.black_on_white()}#{inspect(pid)}#{CF.reset()}] [SubscriptionsWriter] #{msg}"

  ########## STREAMS ###############
  def streams(pid, msg),
    do: "[#{CF.bright_yellow_on_blue()}#{inspect(pid)}#{CF.reset()}] [Streams] #{msg}"

  ############## STREAMS_READER ##############
  def streams_reader(pid, msg),
    do: "[#{CF.bright_yellow_on_blue()}#{inspect(pid)}#{CF.reset()}] [StreamsReader] #{msg}"

  def streams_reader_pool(pid, msg),
    do: "[#{CF.bright_yellow_on_blue()}#{inspect(pid)}#{CF.reset()}] [StreamsReaderPool] #{msg}"

  def streams_reader_worker(pid, msg),
    do: "[#{CF.bright_yellow_on_blue()}#{inspect(pid)}#{CF.reset()}] [StreamsReaderWorker] #{msg}"

  ############## STREAMS_WRITER ##############
  def streams_writer(pid, msg),
    do: "[#{CF.bright_yellow_on_black()}#{inspect(pid)}#{CF.reset()}] [StreamsWriter] #{msg}"

  def streams_writer_pool(pid, msg),
    do: "[#{CF.bright_yellow_on_black()}#{inspect(pid)}#{CF.reset()}] [StreamsWriterPool] #{msg}"

  def streams_writer_system(pid, msg),
    do:
      "[#{CF.bright_yellow_on_black()}#{inspect(pid)}#{CF.reset()}] [StreamsWriterSystem] #{msg}"

  def streams_writer_worker(pid, msg),
    do:
      "[#{CF.bright_yellow_on_black()}#{inspect(pid)}#{CF.reset()}] [StreamsWriterWorker] #{msg}"

  ########## GATEWAY ###############
  def gateway_worker(pid, msg),
    do: "[#{CF.bright_cyan_on_black()}#{inspect(pid)}#{CF.reset()}] [GatewayWorker] #{msg}"

  def gateway_supervisor(pid, msg),
    do: "[#{CF.bright_cyan_on_black()}#{inspect(pid)}#{CF.reset()}] [GatewaySupervisor] #{msg}"

  def gateway_api(pid, msg),
    do: "[#{CF.bright_cyan_on_black()}#{inspect(pid)}#{CF.reset()}] [GatewayApi] #{msg}"

  ################ SNAPSHOTS ################
  def snapshots_system(pid, msg),
    do: "[#{CF.blue_on_yellow()}#{inspect(pid)}#{CF.reset()}] [SnapshotsSystem] #{msg}"

  def snapshots_reader(pid, msg),
    do: "[#{CF.blue_on_yellow()}#{inspect(pid)}#{CF.reset()}] [SnapshotsReader] #{msg}"

  def snapshots_reader_pool(pid, msg),
    do: "[#{CF.blue_on_yellow()}#{inspect(pid)}#{CF.reset()}] [SnapshotsReaderPool] #{msg}"

  def snapshots_reader_worker(pid, msg),
    do: "[#{CF.blue_on_yellow()}#{inspect(pid)}#{CF.reset()}] [SnapshotsReaderWorker] #{msg}"

  def snapshots_writer(pid, msg),
    do: "[#{CF.blue_on_yellow()}#{inspect(pid)}#{CF.reset()}] [SnapshotsWriter] #{msg}"

  def snapshots_writer_pool(pid, msg),
    do: "[#{CF.blue_on_yellow()}#{inspect(pid)}#{CF.reset()}] [SnapshotsWriterPool] #{msg}"

  def snapshots_writer_worker(pid, msg),
    do: "[#{CF.blue_on_yellow()}#{inspect(pid)}#{CF.reset()}] [SnapshotsWriterWorker] #{msg}"
end
