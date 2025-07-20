defmodule OtpAppDiscoveryTest do
  use ExUnit.Case
  
  setup do
    # Store original context to restore after test
    original_context = Process.get(:ex_esdb_otp_app)
    
    on_exit(fn ->
      # Restore original context or delete if none existed
      if original_context do
        Process.put(:ex_esdb_otp_app, original_context)
      else
        Process.delete(:ex_esdb_otp_app)
      end
    end)
    
    :ok
  end
  
  describe "ExESDB.Options context management" do
    test "set_context and get_context work correctly" do
      # Test that context is properly stored and retrieved
      ExESDB.Options.set_context(:test_app)
      assert ExESDB.Options.get_context() == :test_app
      
      # Test with different app
      ExESDB.Options.set_context(:another_app)
      assert ExESDB.Options.get_context() == :another_app
    end
    
    test "get_context returns default when no context is set" do
      # Clear any existing context
      Process.delete(:ex_esdb_otp_app)
      
      # Should return the default
      assert ExESDB.Options.get_context() == :ex_esdb
    end
  end
  
  describe "ExESDB.Options configuration loading" do
    test "app_env loads configuration for specific OTP app" do
      # Set up test configuration
      Application.put_env(:test_discovery_app, :ex_esdb, [
        store_id: :test_store,
        data_dir: "tmp/test",
        db_type: :single
      ])
      
      config = ExESDB.Options.app_env(:test_discovery_app)
      
      assert Keyword.get(config, :store_id) == :test_store
      assert Keyword.get(config, :data_dir) == "tmp/test"
      assert Keyword.get(config, :db_type) == :single
      assert Keyword.get(config, :otp_app) == :test_discovery_app
      
      # Clean up
      Application.delete_env(:test_discovery_app, :ex_esdb)
    end
    
    test "context-aware configuration functions work" do
      # Set up test configuration
      Application.put_env(:context_test_app, :ex_esdb, [
        store_id: :context_store,
        timeout: 15_000
      ])
      
      # Set context and test context-aware functions
      ExESDB.Options.set_context(:context_test_app)
      
      assert ExESDB.Options.store_id() == :context_store
      assert ExESDB.Options.timeout() == 15_000
      
      # Clean up application env (context cleanup handled by setup)
      Application.delete_env(:context_test_app, :ex_esdb)
    end
    
    test "enhanced discovery works with configured apps" do
      # Clear any existing context
      Process.delete(:ex_esdb_otp_app)
      
      # Set up configuration for a test app
      Application.put_env(:discovery_test_app, :ex_esdb, [
        store_id: :discovered_store,
        data_dir: "tmp/discovered"
      ])
      
      # Test that enhanced discovery finds the configured app
      assert ExESDB.Options.get_context_or_discover() == :discovery_test_app
      
      # The context-aware functions should use the discovered context
      assert ExESDB.Options.store_id() == :discovered_store
      assert ExESDB.Options.data_dir() == "tmp/discovered"
      
      # Clean up
      Application.delete_env(:discovery_test_app, :ex_esdb)
      
      # After cleanup, should fall back to default
      assert ExESDB.Options.get_context_or_discover() == :ex_esdb
    end
  end
  
  describe "ExESDB.System auto-discovery" do
    @tag :skip # Skip this test by default as it requires full system setup
    test "can start with auto-discovered OTP app" do
      # Set up test configuration
      Application.put_env(:auto_discovery_app, :ex_esdb, [
        store_id: :auto_discovery_store,
        data_dir: "tmp/auto_discovery",
        timeout: 10_000,
        db_type: :single,
        pub_sub: :test_pubsub
      ])
      
      # Load the app to simulate it being started
      Application.load(:auto_discovery_app)
      
      # Start PubSub for the test
      {:ok, pubsub_pid} = Phoenix.PubSub.Supervisor.start_link([name: :test_pubsub])
      
      try do
        # Test explicit OTP app
        case ExESDB.System.start_link(:auto_discovery_app) do
          {:ok, pid} ->
            assert Process.alive?(pid)
            Process.exit(pid, :shutdown)
          {:error, reason} ->
            flunk("Failed to start with explicit OTP app: #{inspect(reason)}")
        end
      after
        # Clean up
        if Process.alive?(pubsub_pid), do: Process.exit(pubsub_pid, :shutdown)
        Application.delete_env(:auto_discovery_app, :ex_esdb)
      end
    end
  end
end
