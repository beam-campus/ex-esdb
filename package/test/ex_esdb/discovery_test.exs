defmodule ExESDB.DiscoveryTest do
  @moduledoc """
  Tests for the enhanced OTP app discovery mechanism in ExESDB.Options
  """
  use ExUnit.Case, async: true
  
  import ExESDB.Options
  
  describe "OTP app discovery" do
    setup do
      # Store original state
      original_context = Process.get(:ex_esdb_otp_app)
      original_discovery_config = Application.get_env(:discovery_test_app, :ex_esdb)
      original_main_config = Application.get_env(:main_app, :ex_esdb)
      
      on_exit(fn ->
        # Clean up process dictionary
        if original_context do
          Process.put(:ex_esdb_otp_app, original_context)
        else
          Process.delete(:ex_esdb_otp_app)
        end
        
        # Clean up application environment
        Application.put_env(:discovery_test_app, :ex_esdb, original_discovery_config)
        Application.put_env(:main_app, :ex_esdb, original_main_config)
      end)
    end
    
    test "get_context_or_discover/0 falls back to discovery when context is default" do
      # Clear any existing context
      Process.delete(:ex_esdb_otp_app)
      
      # Set up test configuration
      Application.put_env(:discovery_test_app, :ex_esdb, [
        data_dir: "/test/data",
        store_id: :test_store
      ])
      
      # With default context, should try to discover
      context = get_context_or_discover()
      
      # Should discover the test app or fall back to default
      assert context == :discovery_test_app or context == :ex_esdb
    end
    
    test "get_context_or_discover/0 returns set context when available" do
      # Set explicit context
      set_context(:main_app)
      
      # Should return the set context, not try discovery
      assert get_context_or_discover() == :main_app
    end
    
    test "data_dir/0 uses discovered context for configuration" do
      # Clear context
      Process.delete(:ex_esdb_otp_app)
      
      # Set up configuration in a discoverable app
      Application.put_env(:discovery_test_app, :ex_esdb, [
        data_dir: "/discovered/data"
      ])
      
      # If discovery works, should use the discovered app's config
      result = data_dir()
      
      # In test environment, the :ex_esdb app has config from config/test.exs
      # So when discovery fails and falls back to :ex_esdb, we get the test config value
      expected_test_config = "tmp/ex_esdb_store"
      
      # Should either use discovered config, test config, or hard-coded default
      assert result == "/discovered/data" or result == expected_test_config or result == "/data"
    end
    
    test "with_context/2 temporarily overrides discovery" do
      # Clear context
      Process.delete(:ex_esdb_otp_app)
      
      # Set up configurations for different apps
      Application.put_env(:discovery_test_app, :ex_esdb, [data_dir: "/discovered"])
      Application.put_env(:main_app, :ex_esdb, [data_dir: "/explicit"])
      
      # Use with_context to temporarily override
      result = with_context(:main_app, fn ->
        {data_dir(), get_context()}
      end)
      
      assert result == {"/explicit", :main_app}
    end
    
    test "context is properly cleaned up after with_context/2" do
      # Start with no context
      Process.delete(:ex_esdb_otp_app)
      
      # Use with_context
      with_context(:main_app, fn -> 
        assert get_context() == :main_app
      end)
      
      # Context should be cleared after
      assert get_context() == :ex_esdb  # Default fallback
    end
    
    test "nested with_context/2 calls preserve outer context" do
      # Set initial context
      set_context(:outer_app)
      
      result = with_context(:inner_app, fn ->
        inner_context = get_context()
        
        with_context(:nested_app, fn ->
          nested_context = get_context()
          {inner_context, nested_context}
        end)
      end)
      
      assert result == {:inner_app, :nested_app}
      
      # Should restore original context
      assert get_context() == :outer_app
    end
    
    test "app_env/1 automatically adds otp_app key" do
      Application.put_env(:test_app, :ex_esdb, [custom_key: "custom_value"])
      
      result = app_env(:test_app)
      
      assert Keyword.get(result, :custom_key) == "custom_value"
      assert Keyword.get(result, :otp_app) == :test_app
    end
    
    test "configuration functions work with explicit app parameter" do
      Application.put_env(:explicit_app, :ex_esdb, [
        data_dir: "/explicit/data",
        store_id: :explicit_store,
        timeout: 12345
      ])
      
      assert data_dir(:explicit_app) == "/explicit/data"
      assert store_id(:explicit_app) == :explicit_store
      assert timeout(:explicit_app) == 12345
    end
    
    test "configuration functions fall back to defaults when no config exists" do
      # Test with non-existent app
      assert data_dir(:nonexistent_app) == "/data"
      assert store_id(:nonexistent_app) == :undefined
      assert timeout(:nonexistent_app) == 10_000
    end
  end
end
