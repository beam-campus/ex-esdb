
defmodule ExESDB.OptionsTest do
  use ExUnit.Case, async: true
  @doctest ExESDB.Options
  
  import ExESDB.Options
  alias ExESDB.EnVars, as: EnVars

  describe "app_env/1" do
    setup do
      original = Application.get_env(:ex_esdb, :ex_esdb)
      Application.put_env(:ex_esdb, :ex_esdb, [test_key: "test_value"])
      on_exit(fn -> Application.put_env(:ex_esdb, :ex_esdb, original) end)
    end

    test "returns config value for given app" do
      assert app_env(:ex_esdb) == [test_key: "test_value"]
    end
  end

  describe "data_dir/0" do
    setup do
      original_env = System.get_env(EnVars.data_dir())
      original_config = Application.get_env(:ex_esdb, :ex_esdb)
      on_exit(fn ->
        if original_env do
          System.put_env(EnVars.data_dir(), original_env)
        else
          System.delete_env(EnVars.data_dir())
        end
        Application.put_env(:ex_esdb, :ex_esdb, original_config)
      end)
    end

    test "returns env var when set" do
      System.put_env(EnVars.data_dir(), "/custom_data")
      assert data_dir() == "/custom_data"
    end

    test "returns config value when env not set" do
      System.delete_env(EnVars.data_dir())
      Application.put_env(:ex_esdb, :ex_esdb, [data_dir: "/config_data"])
      assert data_dir() == "/config_data"
    end

    test "returns default when neither set" do
      System.delete_env(EnVars.data_dir())
      Application.put_env(:ex_esdb, :ex_esdb, [])
      assert data_dir() == "/data"
    end
  end

  describe "store_id/0" do
    setup do
      original_env = System.get_env(EnVars.store_id())
      original_config = Application.get_env(:ex_esdb, :ex_esdb)
      on_exit(fn ->
        if original_env do
          System.put_env(EnVars.store_id(), original_env)
        else
          System.delete_env(EnVars.store_id())
        end
        Application.put_env(:ex_esdb, :ex_esdb, original_config)
      end)
    end

    test "converts env string to atom" do
      System.put_env(EnVars.store_id(), "custom_store")
      assert store_id() == :custom_store
    end

    test "returns config atom when env not set" do
      System.delete_env(EnVars.store_id())
      Application.put_env(:ex_esdb, :ex_esdb, [store_id: :config_store])
      assert store_id() == :config_store
    end

    test "returns default atom when neither set" do
      System.delete_env(EnVars.store_id())
      Application.put_env(:ex_esdb, :ex_esdb, [])
      assert store_id() == :undefined
    end
  end

  describe "timeout/0" do
    setup do
      original_env = System.get_env(EnVars.timeout())
      original_config = Application.get_env(:ex_esdb, :ex_esdb)
      on_exit(fn ->
        if original_env do
          System.put_env(EnVars.timeout(), original_env)
        else
          System.delete_env(EnVars.timeout())
        end
        Application.put_env(:ex_esdb, :ex_esdb, original_config)
      end)
    end

    test "converts env string to integer" do
      System.put_env(EnVars.timeout(), "5000")
      assert timeout() == 5000
    end

    test "returns config value when env not set" do
      System.delete_env(EnVars.timeout())
      Application.put_env(:ex_esdb, :ex_esdb, [timeout: 7500])
      assert timeout() == 7500
    end

    test "returns default when neither set" do
      System.delete_env(EnVars.timeout())
      Application.put_env(:ex_esdb, :ex_esdb, [])
      assert timeout() == 10_000
    end
  end

  # seed_nodes functionality has been replaced by libcluster configuration

end
