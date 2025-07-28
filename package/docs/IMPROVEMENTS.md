# ExESDB.Options Improvements Summary

## Problem Addressed

The original issue was a `FunctionClauseError` in `ExESDB.System.start_link/1` caused by inconsistent context key usage in the `ExESDB.Options` module. The error occurred when `Application.get_application/1` was called with a PID instead of a module, due to a mismatch in process dictionary keys.

## Root Cause

The issue was in `ExESDB.Options`:
- `set_context/1` used the key `:ex_esdb_otp_app` in the process dictionary
- `get_context/0` tried to retrieve context under `:otp_app`
- This mismatch caused discovery failures and improper OTP app context handling

## Improvements Made

### 1. Fixed Context Key Consistency
- Aligned both `set_context/1` and `get_context/0` to use the same key `:ex_esdb_otp_app`
- Ensures context is properly stored and retrieved

### 2. Enhanced OTP App Discovery
- Added `get_context_or_discover/0` function that tries automatic discovery when context is default
- Implemented `discover_current_app/0` that scans loaded applications for ExESDB configuration
- Uses both Elixir `Application.loaded_applications/0` and Erlang `:application.info()` for comprehensive discovery
- Falls back gracefully to `:ex_esdb` default when discovery fails

### 3. Improved Discovery Algorithm
- **First attempt**: Check loaded applications via `Application.loaded_applications/0` for those with `:ex_esdb` config
- **Second attempt**: Use Erlang's `:application.info()` to check all loaded apps via `:application.get_env/2`
- **Fallback**: Return `nil` to indicate discovery failure, allowing caller to use defaults

### 4. Updated Configuration Functions
- All configuration functions (`data_dir/0`, `store_id/0`, `timeout/0`, etc.) now use `get_context_or_discover/0`
- Automatic OTP app detection works transparently without breaking existing API
- Maintains backward compatibility with explicit app parameter usage

### 5. Enhanced Context Management
- `with_context/2` function provides scoped context switching
- Proper cleanup ensures nested context calls don't leak
- Context restoration works correctly for nested usage patterns

### 6. Comprehensive Testing
- Added `test/ex_esdb/discovery_test.exs` with 9 comprehensive test cases
- Tests cover discovery, context management, nested contexts, and fallback scenarios
- Fixed existing `options_test.exs` to handle automatically added `:otp_app` key
- All 19 tests pass successfully

## Benefits

### 1. **Automatic OTP App Discovery**
- No more manual context setting for simple use cases
- System automatically detects which OTP app has ExESDB configuration
- Reduces boilerplate code for developers

### 2. **Robust Fallback Mechanism**
- When discovery fails, system falls back to sensible defaults
- Handles test environments and edge cases gracefully
- No breaking changes to existing code

### 3. **Improved Developer Experience**
- Just call `ExESDB.System.start_link()` without specifying `otp_app`
- Configuration is automatically discovered from loaded applications
- Manual `otp_app` specification still works for explicit control

### 4. **Better Error Handling**
- Fixed the original `FunctionClauseError`
- Consistent context key usage prevents similar issues
- Graceful degradation when discovery mechanisms fail

### 5. **Umbrella App Support**
- Enhanced support for umbrella applications with multiple OTP apps
- Each app can have its own ExESDB configuration
- Discovery mechanism works across multiple loaded applications

## Migration Guide

### Before (Manual Context Setting)
```elixir
# Had to manually set context
ExESDB.Options.set_context(:my_app)
{:ok, _pid} = ExESDB.System.start_link()
```

### After (Automatic Discovery)
```elixir
# Context is automatically discovered
{:ok, _pid} = ExESDB.System.start_link()

# Or with explicit control when needed
{:ok, _pid} = ExESDB.System.start_link(otp_app: :my_app)
```

## Technical Details

### Discovery Implementation
```elixir
defp discover_current_app do
  # First try loaded applications
  loaded_app = Application.loaded_applications()
  |> Enum.find_value(fn {app, _desc, _vsn} ->
    case Application.get_env(app, :ex_esdb) do
      nil -> nil
      _config -> app
    end
  end)
  
  if loaded_app do
    loaded_app
  else
    # Fall back to Erlang's application info mechanism
    :application.info()
    |> Keyword.get(:loaded, [])
    |> Enum.find_value(fn app ->
      case :application.get_env(app, :ex_esdb) do
        {:ok, _config} -> app
        :undefined -> nil
      end
    end)
  end
end
```

### Context Resolution
```elixir
def get_context_or_discover do
  case get_context() do
    :ex_esdb -> 
      # Try to discover from application environment
      discover_current_app() || :ex_esdb
    context -> 
      context
  end
end
```

## Best Practices

1. **For Simple Applications**: Just call `ExESDB.System.start_link()` - discovery will handle the rest
2. **For Umbrella Applications**: Either rely on discovery or specify `otp_app` explicitly for control
3. **For Testing**: Use `with_context/2` for scoped configuration testing
4. **For Libraries**: Pass explicit `otp_app` parameter to avoid dependency on discovery

The improvements maintain full backward compatibility while providing a much smoother developer experience and fixing the original context management bug.
