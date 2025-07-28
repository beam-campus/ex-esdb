# ExESDB Stream Versioning Simplification

## Problem Statement

The ExESDB stream versioning system was overcomplicated by mixing concepts between event counts and event versions, leading to confusing code and comments that mentioned "1-based" systems when the implementation was already 0-based.

## Previous Implementation Issues

### 1. Confusing Comments
- Comments mentioned "Convert 1-based count to 0-based version" 
- This was misleading since the system was already 0-based

### 2. Complex Version Calculation
- The version calculation in `StreamsWriterWorker.append_events_to_stream/4` was:
  ```elixir
  new_version = current_version + index + 1
  ```
- This mixed the concepts unnecessarily and was hard to understand

### 3. Misleading Documentation
- Documentation implied there was a choice between 1-based and 0-based systems
- In reality, the system was always 0-based with `-1` as a sentinel for empty streams

## Simplified Implementation

### 1. Clarified Comments and Documentation

**Before:**
```elixir
# Convert 1-based count to 0-based version  
{:ok, count} -> count - 1
```

**After:**
```elixir
# Convert event count to last event version (0-based)
# If we have N events, the last event has version N-1
{:ok, event_count} -> event_count - 1
```

### 2. Simplified Version Calculation

**Before:**
```elixir
new_version = current_version + index + 1
```

**After:**
```elixir
# Calculate next version: for new streams (current_version = -1),
# first event gets version 0. For existing streams, increment from current.
new_version = current_version + 1 + index
```

The logic is identical, but the comment makes the intent clearer.

## Versioning Rules (Clarified)

The ExESDB stream versioning system uses **pure 0-based versioning**:

### Stream States
- **Empty stream**: `get_version!` returns `-1` (sentinel value meaning "no events")
- **Stream with 1 event**: `get_version!` returns `0` (version of the single event)
- **Stream with N events**: `get_version!` returns `N-1` (version of the last event)

### Event Versioning
- **First event in any stream**: Always gets version `0`
- **Subsequent events**: Get sequential versions `1, 2, 3, ...`

### Expected Version for Appends
- **New stream**: Use expected version `-1` to append first events
- **Existing stream**: Use the version returned by `get_version!` as expected version

## Examples

### Appending to New Stream
```elixir
# New stream - no events exist
current_version = StreamsHelper.get_version!(store, "new_stream")  # returns -1
events = [event1, event2, event3]

# Append with expected version -1
{:ok, final_version} = StreamsWriter.append_events(store, "new_stream", -1, events)
# final_version will be 2 (version of the last appended event)

# Events get versions: event1=0, event2=1, event3=2
```

### Appending to Existing Stream  
```elixir
# Existing stream with 2 events (versions 0 and 1)
current_version = StreamsHelper.get_version!(store, "existing_stream")  # returns 1
events = [event4, event5]

# Append with expected version 1 
{:ok, final_version} = StreamsWriter.append_events(store, "existing_stream", 1, events)
# final_version will be 3 (version of the last appended event)

# Events get versions: event4=2, event5=3
```

## Benefits of Simplification

### 1. **Clearer Mental Model**
- Pure 0-based system is easier to understand
- No confusion about 1-based vs 0-based concepts
- Sentinel value `-1` is clearly documented as "empty stream"

### 2. **Better Documentation**
- Comments now accurately describe what the code does
- Examples clearly show the versioning behavior
- No misleading references to "conversion" between numbering systems

### 3. **Maintainable Code**
- Version calculations are more straightforward to reason about
- Future developers won't be confused by mixed terminology
- Test cases clearly demonstrate the expected behavior

### 4. **Consistent with Industry Standards**
- Most event stores use 0-based versioning for events
- EventStore DB, Event Store, and others follow this pattern
- Reduces cognitive load for developers familiar with other systems

## Migration Impact

### No Breaking Changes
- The API remains exactly the same
- All existing client code continues to work
- Stream versioning behavior is unchanged

### Internal Benefits Only
- This is purely an internal code cleanup
- Comments and documentation are more accurate
- Future maintenance will be easier

## Verification

Added comprehensive tests in `test/ex_esdb/versioning_test.exs` that verify:
- Version calculation logic for new streams
- Version calculation logic for existing streams  
- Single event appends to both new and existing streams
- Utility functions for version padding and parsing
- Range calculations for forward and backward reading

All tests pass, confirming that the simplified implementation maintains the same behavior while being much clearer to understand and maintain.

## Summary

This change removed unnecessary complexity from the ExESDB stream versioning system by:

1. **Clarifying that the system is purely 0-based** - no more confusing references to "1-based" systems
2. **Improving documentation** - comments now accurately describe the implementation
3. **Simplifying mental model** - developers can easily understand that events are numbered 0, 1, 2, ... with -1 meaning "empty stream"
4. **Maintaining backward compatibility** - no API changes, all existing code continues to work

The system is now much easier to understand, maintain, and extend while providing exactly the same functionality.
