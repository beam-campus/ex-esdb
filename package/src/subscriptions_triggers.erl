-module(subscriptions_triggers).

-export([register_on_created/1, register_on_deleted/1, register_on_updated/1]).

-include_lib("khepri/include/khepri.hrl").

-spec register_on_created(Store :: khepri:store()) -> ok | {error, term()}.
register_on_created(Store) ->
  Filter = feature_filters:when_created(subscriptions),
  PropOpts =
    #{expect_specific_node => false,
      props_to_return =>
        [payload, payload_version, child_list_version, child_list_length, child_names],
      include_root_props => true},
  Id = binary_to_atom(<<"on_subscription_created">>, utf8),
  khepri:register_trigger(Store, Id, Filter, subscriptions_procs:on_create_key(), PropOpts).

-spec register_on_deleted(Store :: atom()) -> ok | {error, term()}.
register_on_deleted(Store) ->
  Filter = feature_filters:when_deleted(subscriptions),
  PropOpts =
    #{expect_specific_node => false,
      props_to_return =>
        [payload, payload_version, child_list_version, child_list_length, child_names],
      include_root_props => true},
  Id = binary_to_atom(<<"on_subscription_deleted">>, utf8),
  khepri:register_trigger(Store, Id, Filter, subscriptions_procs:on_delete_key(), PropOpts).

-spec register_on_updated(Store :: atom()) -> ok | {error, term()}.
register_on_updated(Store) ->
  Filter = feature_filters:when_updated(subscriptions),
  PropOpts =
    #{expect_specific_node => false,
      props_to_return =>
        [payload, payload_version, child_list_version, child_list_length, child_names],
      include_root_props => true},
  Id = binary_to_atom(<<"on_subscription_updated">>, utf8),
  khepri:register_trigger(Store, Id, Filter, subscriptions_procs:on_update_key(), PropOpts).
