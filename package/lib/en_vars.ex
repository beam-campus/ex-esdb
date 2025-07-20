defmodule ExESDB.EnVars do
  @moduledoc """
    This module contains the environment variables that are used by ExESDB
  """
  @doc """
    Returns the data directory. default: `/data`
  """
  def data_dir, do: "EX_ESDB_DATA_DIR"

  @doc """
    Returns the khepri store id. default: `ex_esdb_store`
  """
  def store_id, do: "EX_ESDB_STORE_ID"

  @doc """
    Returns the db type. `single` or `cluster`. default: `single`
  """
  def db_type, do: "EX_ESDB_DB_TYPE"

  @doc """
    Returns the timeout in milliseconds. default: `10_000`
  """
  def timeout, do: "EX_ESDB_TIMEOUT"

  @doc """
    Returns the name of the pub/sub. default: `ex_esdb_pub_sub`
  """
  def pub_sub, do: "EX_ESDB_PUB_SUB"

  @doc """
    Returns the idle writers timeout in milliseconds. default: `10_000`
  """
  def writer_idle_ms, do: "EX_ESDB_WRITER_IDLE_MS"

  @doc """
    Returns the idle readers timeout in milliseconds. default: `10_000`
  """
  def reader_idle_ms, do: "EX_ESDB_READER_IDLE_MS"

  @doc """
    Returns the store description. default: `nil`
  """
  def store_description, do: "EX_ESDB_STORE_DESCRIPTION"

  @doc """
    Returns the store tags as comma-separated values. default: `nil`
  """
  def store_tags, do: "EX_ESDB_STORE_TAGS"

  @doc """
    Returns the persistence interval in milliseconds. default: `5_000`
  """
  def persistence_interval, do: "EX_ESDB_PERSISTENCE_INTERVAL"

  @doc """
    Returns whether persistence is enabled. default: `true`
  """
  def persistence_enabled, do: "EX_ESDB_PERSISTENCE_ENABLED"

  @doc """
    Returns the gossip multicast address. default: `255.255.255.255`
  """
  def gossip_multicast_addr, do: "EX_ESDB_GOSSIP_MULTICAST_ADDR"

  def cluster_secret, do: "EX_ESDB_CLUSTER_SECRET"
end
