defmodule ExESDB.Themes do
  @moduledoc false
  alias BCUtils.ColorFuncs, as: CF
  alias ExESDB.Options, as: Options

  # Helper function to get OTP app context for messages
  defp app_prefix do
    case Options.get_context() do
      :ex_esdb -> ""
      app_name -> "[#{app_name}] "
    end
  end

  def app(pid, msg),
    do: "[#{CF.black_on_blue()}#{inspect(pid)}#{CF.reset()}]#{app_prefix()}[ExESDB Server] #{msg}"

  def system(pid, msg),
    do:
      "[#{CF.black_on_magenta()}#{inspect(pid)}#{CF.reset()}]#{app_prefix()}[ExESDB Main System] #{msg}"

  def core_system(pid, msg),
    do: "[#{CF.black_on_magenta()}#{inspect(pid)}#{CF.reset()}]#{app_prefix()}[CoreSystem] #{msg}"

  def notification_system(pid, msg),
    do:
      "[#{CF.black_on_cyan()}#{inspect(pid)}#{CF.reset()}]#{app_prefix()}[NotificationSystem] #{msg}"

  def store(pid, msg),
    do: "[#{CF.black_on_green()}#{inspect(pid)}#{CF.reset()}]#{app_prefix()}[Store] #{msg}"

  def cluster(pid, msg),
    do: "[#{CF.yellow_on_blue()}#{inspect(pid)}#{CF.reset()}]#{app_prefix()}[Cluster] #{msg}"

  def store_cluster(pid, msg),
    do:
      "[#{CF.yellow_on_black()}#{inspect(pid)}#{CF.reset()}]#{app_prefix()}[StoreCluster] #{msg}"

  def store_coordinator(pid, msg),
    do:
      "[#{CF.white_on_blue()}#{inspect(pid)}#{CF.reset()}]#{app_prefix()}[StoreCoordinator] #{msg}"

  def store_registry(pid, msg),
    do: "[#{CF.white_on_blue()}#{inspect(pid)}#{CF.reset()}]#{app_prefix()}[StoreRegistry] #{msg}"

  def cluster_system(pid, msg),
    do:
      "[#{CF.bright_white_on_blue()}#{inspect(pid)}#{CF.reset()}]#{app_prefix()}[ClusterSystem] #{msg}"

  def node_monitor(pid, msg),
    do:
      "[#{CF.yellow_on_magenta()}#{inspect(pid)}#{CF.reset()}]#{app_prefix()}[NodeMonitor] #{msg}"

  def projector(pid, msg),
    do: "[#{CF.black_on_white()}#{inspect(pid)}#{CF.reset()}]#{app_prefix()}[Projector] #{msg}"

  def monitor(pid, msg),
    do: "[#{CF.yellow_on_magenta()}#{inspect(pid)}#{CF.reset()}]#{app_prefix()}[Monitor] #{msg}"

  def persistence_system(pid, msg),
    do:
      "[#{CF.blue_on_yellow()}#{inspect(pid)}#{CF.reset()}]#{app_prefix()} [PersistenceSystem] #{msg}"

  def persistence_worker(pid, msg),
    do:
      "[#{CF.blue_on_yellow()}#{inspect(pid)}#{CF.reset()}]#{app_prefix()} [PersistenceWorker] #{msg}"

  ############################### EMITTER SYSTEM ###############################
  def emitter_system(pid, msg),
    do:
      "[#{CF.bright_white_on_red()}#{inspect(pid)}#{CF.reset()}]#{app_prefix()} [#{CF.yellow_on_black()}EMITTER SYSTEM#{CF.reset()}] #{CF.white_on_black()}#{msg}#{CF.reset()}"

  def emitter_pool(pid, msg),
    do:
      "[#{CF.bright_white_on_red()}#{inspect(pid)}#{CF.reset()}]#{app_prefix()} [#{CF.yellow_on_black()}EMITTER POOL#{CF.reset()}] #{CF.white_on_black()}#{msg}#{CF.reset()}"

  def emitter_worker(pid, msg),
    do:
      "[#{CF.bright_white_on_red()}#{inspect(pid)}#{CF.reset()}]#{app_prefix()} [#{CF.yellow_on_black()}EMITTER#{CF.reset()}] #{CF.white_on_black()}#{msg}#{CF.reset()}"

  def persistent_emitter_worker(pid, msg),
    do:
      "[#{CF.bright_white_on_red()}#{inspect(pid)}#{CF.reset()}]#{app_prefix()} [#{CF.yellow_on_black()}PERSISTENT EMITTER#{CF.reset()}] #{CF.white_on_black()}#{msg}#{CF.reset()}"

  def pubsub(pid, msg),
    do: "[#{CF.black_on_cyan()}#{inspect(pid)}#{CF.reset()}]#{app_prefix()}[PubSub] #{msg}"

  ############ LEADER SYSTEM ##############
  def leader_system(pid, msg),
    do:
      "[#{CF.black_on_magenta()}#{inspect(pid)}#{CF.reset()}]#{app_prefix()}[LeaderSystem] #{msg}"

  def leader_worker(pid, msg),
    do:
      "[#{CF.black_on_magenta()}#{inspect(pid)}#{CF.reset()}]#{app_prefix()}[LeaderWorker] #{msg}"

  def leader_tracker(pid, msg),
    do:
      "[#{CF.black_on_magenta()}#{inspect(pid)}#{CF.reset()}]#{app_prefix()}[LeaderTracker] #{msg}"

  ######## SUBSCRIPTIONS ############
  def subscriptions(pid, msg),
    do:
      "[#{CF.black_on_white()}#{inspect(pid)}#{CF.reset()}]#{app_prefix()}[Subscriptions] #{msg}"

  def subscriptions_reader(pid, msg),
    do:
      "[#{CF.black_on_white()}#{inspect(pid)}#{CF.reset()}]#{app_prefix()}[SubscriptionsReader] #{msg}"

  def subscriptions_writer(pid, msg),
    do:
      "[#{CF.black_on_white()}#{inspect(pid)}#{CF.reset()}]#{app_prefix()}[SubscriptionsWriter] #{msg}"

  ########## STREAMS ###############
  def streams(pid, msg),
    do:
      "[#{CF.bright_yellow_on_blue()}#{inspect(pid)}#{CF.reset()}]#{app_prefix()}[Streams] #{msg}"

  ############## STREAMS_READER ##############
  def streams_reader(pid, msg),
    do:
      "[#{CF.bright_yellow_on_blue()}#{inspect(pid)}#{CF.reset()}]#{app_prefix()}[StreamsReader] #{msg}"

  def streams_reader_pool(pid, msg),
    do:
      "[#{CF.bright_yellow_on_blue()}#{inspect(pid)}#{CF.reset()}]#{app_prefix()}[StreamsReaderPool] #{msg}"

  def streams_reader_worker(pid, msg),
    do:
      "[#{CF.bright_yellow_on_blue()}#{inspect(pid)}#{CF.reset()}]#{app_prefix()}[StreamsReaderWorker] #{msg}"

  ############## STREAMS_WRITER ##############
  def streams_writer(pid, msg),
    do:
      "[#{CF.bright_yellow_on_black()}#{inspect(pid)}#{CF.reset()}]#{app_prefix()}[StreamsWriter] #{msg}"

  def streams_writer_pool(pid, msg),
    do:
      "[#{CF.bright_yellow_on_black()}#{inspect(pid)}#{CF.reset()}]#{app_prefix()}[StreamsWriterPool] #{msg}"

  def streams_writer_system(pid, msg),
    do:
      "[#{CF.bright_yellow_on_black()}#{inspect(pid)}#{CF.reset()}]#{app_prefix()}[StreamsWriterSystem] #{msg}"

  def streams_writer_worker(pid, msg),
    do:
      "[#{CF.bright_yellow_on_black()}#{inspect(pid)}#{CF.reset()}]#{app_prefix()}[StreamsWriterWorker] #{msg}"

  ########## GATEWAY ###############
  def gateway_worker(pid, msg),
    do:
      "[#{CF.bright_cyan_on_black()}#{inspect(pid)}#{CF.reset()}]#{app_prefix()}[GatewayWorker] #{msg}"

  def gateway_supervisor(pid, msg),
    do:
      "[#{CF.bright_cyan_on_black()}#{inspect(pid)}#{CF.reset()}]#{app_prefix()}[GatewaySupervisor] #{msg}"

  def gateway_api(pid, msg),
    do:
      "[#{CF.bright_cyan_on_black()}#{inspect(pid)}#{CF.reset()}]#{app_prefix()}[GatewayApi] #{msg}"

  ################ SNAPSHOTS ################
  def snapshots_system(pid, msg),
    do:
      "[#{CF.blue_on_yellow()}#{inspect(pid)}#{CF.reset()}]#{app_prefix()}[SnapshotsSystem] #{msg}"

  def snapshots_reader(pid, msg),
    do:
      "[#{CF.blue_on_yellow()}#{inspect(pid)}#{CF.reset()}]#{app_prefix()}[SnapshotsReader] #{msg}"

  def snapshots_reader_pool(pid, msg),
    do:
      "[#{CF.blue_on_yellow()}#{inspect(pid)}#{CF.reset()}]#{app_prefix()}[SnapshotsReaderPool] #{msg}"

  def snapshots_reader_worker(pid, msg),
    do:
      "[#{CF.blue_on_yellow()}#{inspect(pid)}#{CF.reset()}]#{app_prefix()}[SnapshotsReaderWorker] #{msg}"

  def snapshots_writer(pid, msg),
    do:
      "[#{CF.blue_on_yellow()}#{inspect(pid)}#{CF.reset()}]#{app_prefix()}[SnapshotsWriter] #{msg}"

  def snapshots_writer_pool(pid, msg),
    do:
      "[#{CF.blue_on_yellow()}#{inspect(pid)}#{CF.reset()}]#{app_prefix()}[SnapshotsWriterPool] #{msg}"

  def snapshots_writer_worker(pid, msg),
    do:
      "[#{CF.blue_on_yellow()}#{inspect(pid)}#{CF.reset()}]#{app_prefix()}[SnapshotsWriterWorker] #{msg}"
end
