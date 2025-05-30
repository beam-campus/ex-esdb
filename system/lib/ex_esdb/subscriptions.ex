defmodule ExESDB.Subscriptions do
  @moduledoc """
   Provides functions for working with event store subscriptions.
  """
  @type store :: atom()
  @type stream :: String.t()
  @type subscription_name :: String.t()
  @type error :: term

  use GenServer

  alias ExESDB.Emitters
  require Logger

  @doc """
    Create a transient subscription for a specific stream or for all streams.
  """
  @spec subscribe(
          store :: store,
          stream :: stream
        ) ::
          :ok | {:error, error}
  def subscribe(store, stream \\ "$all") do
    store
    |> Emitters.start_stream_emitter(stream)

    case store
         |> :khepri.put(
           [:subscriptions, stream],
           %{
             subscriber: self(),
             start_from: 0,
             opts: []
           }
         ) do
      :ok ->
        ExESDB.Emitters.start_stream_emitter(store, stream)
        :ok

      {:error, reason} ->
        {:error, reason}
    end
  end

  @spec subscribe_to(
          store :: store,
          stream :: String.t(),
          subscription_name :: subscription_name,
          subscriber :: pid,
          start_from :: integer,
          opts :: Keyword.t()
        ) :: :ok | {:error, error}
  def subscribe_to(
        store,
        stream,
        subscription_name,
        subscriber,
        start_from \\ 0,
        opts \\ []
      ) do
    case store
         |> :khepri.put(
           [:subscriptions, stream, subscription_name],
           %{
             subscriber: subscriber,
             start_from: start_from,
             opts: opts
           }
         ) do
      :ok ->
        store
        |> Emitters.start_stream_emitter(stream)

        :ok

      {:error, reason} ->
        {:error, reason}
    end
  end

  def unsubscribe(store, subscription_name) do
    store
    |> :khepri.delete!([:subscriptions, subscription_name])
  end

  @doc """
    Delete a subscription.
  """
  @spec delete_subscription(
          store :: any,
          subscription_name :: subscription_name,
          stream :: stream
        ) :: :ok | {:error, error}
  def delete_subscription(store, subscription_name, stream \\ "$all") do
    store
    |> :khepri.delete!([:subscriptions, subscription_name, stream])
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
