defmodule ExESDB.Commanded.Adapter do
  @moduledoc """
    An adapter for Commanded to use ExESDB as the event store.
    for reference, see: https://hexdocs.pm/commanded/Commanded.EventStore.Adapter.html
  """
  @behaviour Commanded.EventStore.Adapter

  require Logger
  alias ExESDB.EventStore, as: Store
  alias ExESDB.Options, as: Options
  alias ExESDB.Streams, as: Streams
  alias ExESDB.Subscriptions, as: Subscriptions

  alias ExESDB.Commanded.Mapper, as: Mapper

  @type adapter_meta :: map
  @type application :: Commanded.Application.t()
  @type config :: Keyword.t()
  @type stream_uuid :: String.t()
  @type start_from :: :origin | :current | integer
  @type expected_version :: :any_version | :no_stream | :stream_exists | non_neg_integer
  @type subscription_name :: String.t()
  @type subscription :: any
  @type subscriber :: pid
  @type source_uuid :: String.t()
  @type error :: term

  #  @spec ack_event(
  #  adapter_meta(),
  #  pid(),
  #  Commanded.EventStore.EventData.t()) :: :ok | {:error, error()})
  @impl true
  def ack_event(meta, pid, event) do
    Logger.warning(
      "ack_event/3 is not implemented for #{inspect(meta)}, #{inspect(pid)}, #{inspect(event)}"
    )

    :ok
  end

  @doc """
    Append one or more events to a stream atomically.
  """
  @spec append_to_stream(
          adapter_meta :: map(),
          stream_uuid :: String.t(),
          expected_version :: integer(),
          events :: list(Commanded.EventStore.EventData.t()),
          opts :: Keyword.t()
        ) :: :ok | {:error, :wrong_expected_version} | {:error, error()}
  @impl true
  def append_to_stream(adapter_meta, stream_uuid, expected_version, events, _opts) do
    store =
      Map.get(adapter_meta, :store_id)

    new_events =
      events
      |> Enum.map(&Mapper.to_new_event/1)

    store
    |> Store.append_to_stream(stream_uuid, expected_version, new_events)
  end

  @doc """
  Return a child spec defining all processes required by the event store.
  """
  @impl Commanded.EventStore.Adapter
  def child_spec(application, opts) do
    meta =
      opts
      |> Keyword.put(:application, application)
      |> Map.new()

    {:ok, [ExESDB.System.child_spec(opts)], meta}
  end

  @impl true
  def delete_snapshot(adapter_meta, source_uuid) do
    Logger.warning(
      "delete_snapshot/4 is not implemented for #{inspect(adapter_meta)}, #{inspect(source_uuid)}"
    )

    {:error, :not_implemented}
  end

  @impl true
  def delete_subscription(adapter_meta, arg2, subscription_name) do
    Logger.warning(
      "delete_subscription/4 is not implemented for #{inspect(adapter_meta)}, #{inspect(arg2)}, #{inspect(subscription_name)}"
    )

    {:error, :not_implemented}
  end

  @impl true
  def read_snapshot(adapter_meta, stream_uuid) do
    Logger.warning(
      "read_snapshot/5 is not implemented for #{inspect(adapter_meta)}, #{inspect(stream_uuid)}"
    )

    {:error, :not_implemented}
  end

  @impl true
  def record_snapshot(adapter_meta, snapshot_data) do
    Logger.warning(
      "record_snapshot/3 is not implemented for #{inspect(adapter_meta)}, #{inspect(snapshot_data)}"
    )

    {:error, :not_implemented}
  end

  @impl true
  def stream_forward(adapter_meta, stream_uuid, start_version, read_batch_size) do
    Logger.warning(
      "stream_forward/5 is not implemented for #{inspect(adapter_meta)}, #{inspect(stream_uuid)}, #{inspect(start_version)}, #{inspect(read_batch_size)}"
    )

    {:error, :not_implemented}
    # {:ok, stream} = Adapter.open_stream(stream_uuid, opts)
    # ExESDB.stream_forward(stream, start_version, read_batch_size)
  end

  @impl true
  def subscribe(adapter_meta, arg2) do
    Logger.warning(
      "subscribe/2 is not implemented for #{inspect(adapter_meta)}, #{inspect(arg2)}"
    )

    {:error, :not_implemented}
  end

  @impl true
  def subscribe_to(adapter_meta, arg2, subscription_name, subscriber, start_from, opts) do
    Logger.warning(
      "subscribe_to/7 is not implemented for #{inspect(adapter_meta)}, #{inspect(arg2)}, #{inspect(subscription_name)}, #{inspect(subscriber)}, #{inspect(start_from)}, #{inspect(opts)}"
    )

    {:error, :not_implemented}
  end

  @impl true
  def unsubscribe(adapter_meta, subscription_name) do
    Logger.warning(
      "unsubscribe/3 is not implemented for #{inspect(adapter_meta)}, #{inspect(subscription_name)}"
    )

    {:error, :not_implemented}
  end
end
