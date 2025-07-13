defmodule ExESDB.Snapshots do
  @moduledoc """
    The ExESDB Snapshots SubSystem.
  """
  use Supervisor

  require Logger

  import ExESDB.Khepri.Conditions

  @type khepri_condition ::
          ExESDB.Khepri.Conditions.if_all()
          | ExESDB.Khepri.Conditions.if_any()
          | ExESDB.Khepri.Conditions.if_name_matches()
          | ExESDB.Khepri.Conditions.if_path_matches()
          | ExESDB.Khepri.Conditions.if_has_data()
          | ExESDB.Khepri.Conditions.if_has_payload()
          | ExESDB.Khepri.Conditions.if_has_sproc()
          | ExESDB.Khepri.Conditions.if_data_matches()
          | ExESDB.Khepri.Conditions.if_node_exists()
          | ExESDB.Khepri.Conditions.if_payload_version()
          | ExESDB.Khepri.Conditions.if_child_list_version()
          | ExESDB.Khepri.Conditions.if_child_list_length()

  def start_link(opts),
    do:
      Supervisor.start_link(
        __MODULE__,
        opts,
        name: __MODULE__
      )

  @impl true
  def init(_) do
    children = [
      {PartitionSupervisor, child_spec: DynamicSupervisor, name: ExESDB.SnapshotsWriters},
      {PartitionSupervisor, child_spec: DynamicSupervisor, name: ExESDB.SnapshotsReaders}
    ]

    ret = Supervisor.init(children, strategy: :one_for_one)
    Logger.info("SnapshotsSystem #{inspect(self())} is UP.")
    ret
  end

  @doc """
  ## Description
    Returns the key for a snapshot as a Khepri Path.
  ## Examples
      iex> ExESDB.Snapshots.path("source_uuid", "stream_uuid", 1)
      [:snapshots, "source_uuid", "stream_uuid", "000000001"]
  """
  @spec path(
          source_uuid :: String.t(),
          stream_uuid :: String.t(),
          version :: non_neg_integer()
        ) :: list()
  def path(source_uuid, stream_uuid, version)
      when is_binary(source_uuid) and
             is_binary(stream_uuid) and
             is_integer(version) and
             version >= 0 do
    padded_version =
      version
      |> Integer.to_string()
      |> String.pad_leading(10, "0")

    [:snapshots, source_uuid, stream_uuid, padded_version]
  end
end
