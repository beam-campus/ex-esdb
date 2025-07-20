defmodule ExESDB.HashRing do
  @moduledoc """
    Provides functions for distributing load over the cluster.
  """

  def get_node_for_stream(stream_id) do
    nodes = [Node.self() | Node.list()]
    hash = :erlang.phash2(stream_id, length(nodes))
    Enum.at(nodes, hash)
  end

  def get_core_for_stream(stream_id) do
    core_count = System.schedulers_online()
    :erlang.phash2(stream_id, core_count)
  end
end
