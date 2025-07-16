defmodule ExESDB.EventStoreTest do
  use ExUnit.Case
  doctest ExESDB.EventStore

  alias ExESDB.EventStore
  alias ExESDB.Options, as: Options

  require Logger

  setup do
    opts = Options.app_env(:ex_esdb)

    start_supervised!({EventStore, opts})

    on_exit(fn ->
      File.rm_rf!(opts[:data_dir])
    end)

    opts
  end

  describe "GIVEN a valid set of options" do
    test "WHEN the EventStore is started
          THEN the EventStore is started and the pid is returned" do
      opts = Options.app_env(:ex_esdb)
      {:ok, res} = EventStore.start_link(opts)
      Logger.warning("EventStore pid: #{inspect(res, pretty: true)}")
    end
  end

  describe "append_to_stream/3" do
    test "appends events to a new stream" do
      opts = Options.app_env(:ex_esdb)
      stream_name = "test_stream"
      events = [%{type: "TestEvent", data: "test data"}]

      assert {:ok, 1} =
        Options.store
        |> EventStore.append_to_stream(stream_name, 0, events)

      res = Options.store
            |> EventStore.read_stream_forward(stream_name, 0, 1)
      Logger.warning("stream: #{inspect(res, pretty: true)}")
    end

    test "appends events to an existing stream" do
      %{store_id: store_id} = Config.fetch_env!(:node_app)
      stream_name = "test_stream"
      events1 = [%{type: "TestEvent1", data: "test data 1"}]
      events2 = [%{type: "TestEvent2", data: "test data 2"}]

      assert {:ok, 1} = EventStore.append_to_stream(store_id, stream_name, 0, events1)
      assert {:ok, 2} = EventStore.append_to_stream(store_id, stream_name, 1, events2)
    end

    @tag :skip
    test "returns error when expected version is incorrect" do
      stream_name = "test_stream"
      events = [%{type: "TestEvent", data: "test data"}]

      assert {:error, :wrong_expected_version} =
               EventStore.append_to_stream(stream_name, 1, events)
    end
  end

  describe "read_stream_forward/3" do
    @tag :skip
    test "reads events from a stream" do
      stream_name = "test_stream"

      events = [
        %{type: "TestEvent1", data: "test data 1"},
        %{type: "TestEvent2", data: "test data 2"},
        %{type: "TestEvent3", data: "test data 3"}
      ]

      EventStore.append_to_stream(stream_name, 0, events)

      assert {:ok, read_events} = EventStore.read_stream_forward(stream_name, 1, 2)
      assert length(read_events) == 2
      assert Enum.at(read_events, 0) == Enum.at(events, 0)
      assert Enum.at(read_events, 1) == Enum.at(events, 1)
    end

    @tag :skip
    test "returns empty list when reading beyond stream end" do
      stream_name = "test_stream"
      events = [%{type: "TestEvent", data: "test data"}]

      EventStore.append_to_stream(stream_name, 0, events)

      assert {:ok, []} = EventStore.read_stream_forward(stream_name, 2, 2)
    end
  end

  describe "stream_version/1" do
    @tag :skip
    test "returns the current version of a stream" do
      stream_name = "test_stream"

      events = [
        %{type: "TestEvent1", data: "test data 1"},
        %{type: "TestEvent2", data: "test data 2"}
      ]

      EventStore.append_to_stream(stream_name, 0, events)

      assert {:ok, 2} = EventStore.stream_version(stream_name)
    end

    @tag :skip
    test "returns 0 for a non-existent stream" do
      stream_name = "non_existent_stream"

      assert {:ok, 0} = EventStore.stream_version(stream_name)
    end
  end
end
