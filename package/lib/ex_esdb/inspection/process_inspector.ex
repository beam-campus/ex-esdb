defmodule ExESDB.Inspection.ProcessInspector do
  @moduledoc """
  Inspects processes related to the ExESDB system.
  
  Provides functionality to list, categorize, and analyze processes
  for health monitoring and debugging.
  """
  
  use GenServer
  
  # API
  
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  def list_processes() do
    GenServer.call(__MODULE__, :list_processes)
  end
  
  # GenServer callbacks
  
  @impl true
  def init(_opts) do
    {:ok, %{}}
  end
  
  @impl true
  def handle_call(:list_processes, _from, state) do
    processes = fetch_processes()
    {:reply, processes, state}
  end
  
  # Private functions
  
  defp fetch_processes do
    Process.registered()
    |> Enum.filter(&process_filter/1)
    |> Enum.map(&process_info/1)
  end
  
  defp process_filter(name) do
    name_str = to_string(name)
    String.contains?(name_str, "ex_esdb")
  end
  
  defp process_info(name) do
    pid = Process.whereis(name)
    info = if pid, do: Process.info(pid), else: []
    {name, pid, info}
  end
end

