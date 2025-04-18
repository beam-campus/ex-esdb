defmodule ExESDB.Subscriptions do
  @moduledoc """
   Provides functions for working with event store subscriptions.
  """
  @type store :: :khepri.store()
  @type stream_uuid :: any()
  @type subscription_name :: String.t()
  @type error :: term

  use GenServer

  @spec register_emitter(
          store :: :khepri.store(),
          stream_uuid :: stream_uuid | :all,
          pub_sub :: atom()
        ) :: :ok | {:error :: error}
  defp(register_emitter(store, stream_uuid, pub_sub),
    do:
      store
      |> :func_registrations.register_emitter(pub_sub, stream_uuid)
  )

  @doc """
    Subscribe to a all events in a store, or a specific stream.
  """
  @spec subscribe_to(
          store :: store,
          stream_uuid :: :all | stream_uuid,
          subscription_name :: subscription_name,
          subscriber :: pid,
          start_from :: integer,
          opts :: Keyword.t()
        ) :: :ok | {:error, error}
  def subscribe_to(
        store,
        stream_uuid,
        subscription_name,
        subscriber,
        start_from \\ 0,
        opts \\ []
      ) do
    case store
         |> :khepri.put(
           [:subscriptions, stream_uuid, subscription_name],
           %{
             subscriber: subscriber,
             start_from: start_from,
             opts: opts
           }
         ) do
      :ok ->
        register_emitter(store, stream_uuid, subscriber)
        :ok

      {:error, reason} ->
        {:error, reason}
    end
  end

  def unsubscribe(store, subscription_name) do
    case store
         |> :khepri.delete!([:subscriptions, subscription_name]) do
      {:ok, _} ->
        :ok

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
    Delete a subscription.
  """
  @spec delete_subscription(
          store :: any,
          subscription_name :: subscription_name,
          stream_uuid :: stream_uuid | :all
        ) :: :ok | {:error, error}
  def delete_subscription(store, subscription_name, stream_uuid \\ :all) do
    case store
         |> :khepri.delete!([:subscriptions, subscription_name, stream_uuid]) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  def all(store) do
    case store
         |> :khepri.get([:subscriptions]) do
      {:ok, result} ->
        result
        |> Enum.map(fn item -> item end)

      {:error, reason} ->
        {:error, reason}
    end
  end

  def by_name(store, subscription_name) do
    case store
         |> :khepri.get([:subscriptions, subscription_name]) do
      {:ok, result} ->
        result
        |> Enum.map(fn item -> item end)

      {:error, reason} ->
        {:error, reason}
    end
  end

  ####### PLUMBING #######
  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]},
      type: :worker,
      restart: :permanent,
      shutdown: 5000
    }
  end

  def start_link(opts) do
    GenServer.start_link(
      __MODULE__,
      opts,
      name: __MODULE__
    )
  end

  @impl true
  def init(opts) do
    {:ok, opts}
  end
end
