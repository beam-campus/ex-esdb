defmodule ExESDB.Inspection.TreeInspector do
  @moduledoc """
  Inspects the supervision tree of the ExESDB system.

  Provides visualization and analysis of the system's supervision
  hierarchy to aid in debugging and monitoring.
  """

  use GenServer

  # API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def view_supervision_tree(store_id \\ nil) do
    GenServer.call(__MODULE__, {:view_supervision_tree, store_id})
  end

  # GenServer callbacks

  @impl true
  def init(_opts) do
    {:ok, %{}}
  end

  @impl true
  def handle_call({:view_supervision_tree, store_id}, _from, state) do
    store_id = store_id || :default_store
    tree = fetch_supervision_tree(store_id)
    {:reply, tree, state}
  end

  # Private functions

  defp fetch_supervision_tree(store_id) do
    system_name = ExESDB.System.system_name(store_id)
    pid = Process.whereis(system_name)
    build_tree(system_name, pid, 0)
  end

  defp build_tree(name, pid, depth) do
    if Process.alive?(pid) do
      children = Supervisor.which_children(pid)
      |> Enum.map(fn {child_id, child_pid, type, _modules} ->
        child_tree = if type == :supervisor and child_pid != :undefined do
          build_tree(child_id, child_pid, depth + 1)
        else
          nil
        end
        %{
          id: child_id,
          pid: child_pid,
          type: type,
          alive: Process.alive?(child_pid),
          children: child_tree
        }
      end)

      %{
        name: name,
        pid: pid,
        alive: Process.alive?(pid),
        depth: depth,
        children: children
      }
    else
      %{
        name: name,
        pid: :undefined,
        alive: false,
        depth: depth,
        children: []
      }
    end
  end
end

