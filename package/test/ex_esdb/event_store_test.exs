defmodule ExESDB.EventStoreTest do
  use ExUnit.Case
  doctest ExESDB.Store

  alias ExESDB.Store
  alias ExESDB.Options, as: Options

  require Logger

  setup do
    opts = Options.app_env(:ex_esdb)

    start_supervised!({Store, opts})

    on_exit(fn ->
      File.rm_rf!(opts[:data_dir])
    end)

    opts
  end

  describe "GIVEN a valid set of options" do
    test "WHEN the Store is started
          THEN the Store is started and the pid is returned" do
      opts = Options.app_env(:ex_esdb)
      {:ok, res} = Store.start_link(opts)
      Logger.warning("Store pid: #{inspect(res, pretty: true)}")
    end
  end

  describe "Store state" do
    test "can get store state" do
      {:ok, state} = Store.get_state()
      assert is_list(state)
      assert Keyword.has_key?(state, :config)
      assert Keyword.has_key?(state, :store)
    end
  end

  describe "Store naming" do
    test "can get store name" do
      store_name = Store.store_name("test_store")
      assert store_name == {:ex_esdb_store, "test_store"}
    end

    test "can get store name for nil" do
      store_name = Store.store_name(nil)
      assert store_name == ExESDB.Store
    end
  end
end
