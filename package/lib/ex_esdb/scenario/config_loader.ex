defmodule ExESDB.Scenario.ConfigLoader do
  @moduledoc """
  Loads and validates scenario configurations from various sources.
  
  Supports loading from JSON files, YAML files, and Elixir configuration
  for custom test scenarios.
  """
  
  use GenServer
  
  # API
  
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  def load_config(path) do
    GenServer.call(__MODULE__, {:load_config, path})
  end
  
  def validate_config(config) do
    GenServer.call(__MODULE__, {:validate_config, config})
  end
  
  def list_builtin_scenarios() do
    GenServer.call(__MODULE__, :list_builtin_scenarios)
  end
  
  # GenServer callbacks
  
  @impl true
  def init(_opts) do
    {:ok, %{cache: %{}}}
  end
  
  @impl true
  def handle_call({:load_config, path}, _from, state) do
    case load_config_file(path) do
      {:ok, config} ->
        case validate_scenario_config(config) do
          :ok ->
            new_cache = Map.put(state.cache, path, config)
            {:reply, {:ok, config}, %{state | cache: new_cache}}
          {:error, reason} ->
            {:reply, {:error, reason}, state}
        end
      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end
  
  @impl true
  def handle_call({:validate_config, config}, _from, state) do
    result = validate_scenario_config(config)
    {:reply, result, state}
  end
  
  @impl true
  def handle_call(:list_builtin_scenarios, _from, state) do
    scenarios = builtin_scenarios()
    {:reply, scenarios, state}
  end
  
  # Private functions
  
  defp load_config_file(path) do
    case File.read(path) do
      {:ok, content} ->
        case Path.extname(path) do
          ".json" -> Jason.decode(content)
          ".yaml" -> YamlElixir.read_from_string(content)
          ".yml" -> YamlElixir.read_from_string(content)
          _ -> {:error, "Unsupported file format"}
        end
      {:error, reason} ->
        {:error, "Cannot read file: #{inspect(reason)}"}
    end
  rescue
    _ -> {:error, "Failed to parse configuration file"}
  end
  
  defp validate_scenario_config(config) do
    required_fields = ["name", "steps"]
    
    case validate_required_fields(config, required_fields) do
      :ok ->
        validate_steps(Map.get(config, "steps", []))
      error ->
        error
    end
  end
  
  defp validate_required_fields(config, required_fields) do
    missing_fields = Enum.filter(required_fields, fn field ->
      not Map.has_key?(config, field)
    end)
    
    case missing_fields do
      [] -> :ok
      fields -> {:error, "Missing required fields: #{Enum.join(fields, ", ")}"}
    end
  end
  
  defp validate_steps(steps) when is_list(steps) do
    Enum.reduce_while(steps, :ok, fn step, acc ->
      case validate_step(step) do
        :ok -> {:cont, acc}
        error -> {:halt, error}
      end
    end)
  end
  
  defp validate_steps(_), do: {:error, "Steps must be a list"}
  
  defp validate_step(step) do
    case Map.get(step, "action") do
      nil -> {:error, "Step missing 'action' field"}
      action when action in ["wait", "load_test", "custom"] -> :ok
      action -> {:error, "Unknown action: #{action}"}
    end
  end
  
  defp builtin_scenarios do
    %{
      high_load: %{
        name: "High Load Test",
        description: "Simulates high CPU/memory load on the system",
        parameters: [:intensity, :duration]
      },
      node_failure: %{
        name: "Node Failure Simulation",
        description: "Simulates various types of node failures",
        parameters: [:target_node, :failure_type]
      },
      mixed_load: %{
        name: "Mixed Load Pattern",
        description: "Complex scenario with varying load patterns",
        parameters: [:config_path]
      }
    }
  end
end
