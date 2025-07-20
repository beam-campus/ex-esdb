-module(streams_triggers).

-include_lib("khepri/include/khepri.hrl").

-export([register_on_new_event/3]).

-spec register_on_new_event(Store :: khepri:store_id(),
                            Id :: string(),
                            Filter :: khepri_evf:event_filter()) ->
                             ok | {error, term()}.
register_on_new_event(Store, Id, Filter) ->
  Topic = emitter_group:topic(Store, Id),
  PropOpts =
    #{expect_specific_node => false,
      props_to_return =>
        [payload, payload_version, child_list_version, child_list_length, child_names],
      include_root_props => true},
  TriggerId = binary_to_atom(Id, utf8),
  khepri:register_trigger(Store, TriggerId, Filter, [procs, on_new_event, Topic], PropOpts).
