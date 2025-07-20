-module(subscriptions).

-export([setup_tracking/2]).

setup_tracking(Store, PidOrPids) ->
  tracker_group:join(Store, subscriptions, PidOrPids),
  subscriptions_procs:put_on_create_func(Store),
  subscriptions_triggers:register_on_created(Store),
  subscriptions_procs:put_on_delete_func(Store),
  subscriptions_triggers:register_on_deleted(Store),
  subscriptions_procs:put_on_update_func(Store),
  subscriptions_triggers:register_on_updated(Store),
  ok.
