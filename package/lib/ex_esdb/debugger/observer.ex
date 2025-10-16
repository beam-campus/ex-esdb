defmodule ExESDB.Debugger.Observer do
  @moduledoc """
  Real-time observation module for ExESDB debugging.
  
  Provides functionality to observe system metrics, process behavior,
  and performance characteristics in real-time.
  """
  
  use GenServer
  
  # API
  
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  def start_observation(target, opts \\ []) do
    GenServer.call(__MODULE__, {:start_observation, target, opts})
  end
  
  def stop_observation(observation_id) do
    GenServer.call(__MODULE__, {:stop_observation, observation_id})
  end
  
  def list_observations() do
    GenServer.call(__MODULE__, :list_observations)
  end
  
  def get_observation_data(observation_id) do
    GenServer.call(__MODULE__, {:get_observation_data, observation_id})
  end
  
  # GenServer callbacks
  
  @impl true
  def init(_opts) do
    {:ok, %{observations: %{}, counter: 0}}
  end
  
  @impl true
  def handle_call({:start_observation, target, opts}, _from, state) do
    observation_id = "obs_#{state.counter + 1}"
    interval = Keyword.get(opts, :interval, 1000)
    
    observation = %{
      id: observation_id,
      target: target,
      started_at: System.system_time(:millisecond),
      data_points: 0,
      interval: interval,
      timer: nil
    }
    
    # Start periodic collection
    timer = Process.send_after(self(), {:collect_data, observation_id}, interval)
    observation = %{observation | timer: timer}
    
    new_observations = Map.put(state.observations, observation_id, observation)
    new_state = %{state | observations: new_observations, counter: state.counter + 1}
    
    {:reply, {:ok, observation_id}, new_state}
  end
  
  @impl true
  def handle_call({:stop_observation, observation_id}, _from, state) do
    case Map.get(state.observations, observation_id) do
      nil ->
        {:reply, {:error, :not_found}, state}
      observation ->
        if observation.timer do
          Process.cancel_timer(observation.timer)
        end
        new_observations = Map.delete(state.observations, observation_id)
        {:reply, :ok, %{state | observations: new_observations}}
    end
  end
  
  @impl true
  def handle_call(:list_observations, _from, state) do
    observations = Map.values(state.observations)
    {:reply, observations, state}
  end
  
  @impl true
  def handle_call({:get_observation_data, observation_id}, _from, state) do
    case Map.get(state.observations, observation_id) do
      nil ->
        {:reply, {:error, :not_found}, state}
      observation ->
        # Return basic observation data for now
        data = collect_target_data(observation.target)
        {:reply, {:ok, data}, state}
    end
  end
  
  @impl true
  def handle_info({:collect_data, observation_id}, state) do
    case Map.get(state.observations, observation_id) do
      nil ->
        {:noreply, state}
      observation ->
        # Collect data point
        _data = collect_target_data(observation.target)
        
        # Schedule next collection
        timer = Process.send_after(self(), {:collect_data, observation_id}, observation.interval)
        
        # Update observation
        updated_observation = %{observation | 
          data_points: observation.data_points + 1,
          timer: timer
        }
        
        new_observations = Map.put(state.observations, observation_id, updated_observation)
        {:noreply, %{state | observations: new_observations}}
    end
  end
  
  @impl true
  def handle_info(_msg, state) do
    {:noreply, state}
  end
  
  # Private functions
  
  defp collect_target_data(target) do
    case target do
      :system_metrics ->
        %{
          memory: :erlang.memory(),
          process_count: length(Process.list()),
          timestamp: System.system_time(:millisecond)
        }
      :process_metrics ->
        %{
          processes: length(Process.list()),
          timestamp: System.system_time(:millisecond)
        }
      :memory_usage ->
        %{
          memory: :erlang.memory(),
          timestamp: System.system_time(:millisecond)
        }
      _ ->
        %{
          target: target,
          timestamp: System.system_time(:millisecond),
          message: "Unknown target type"
        }
    end
  end
end