-module(configs_triggers).

-export([register_on_created/1, register_on_deleted/1, register_on_updated/1]).

-include_lib("khepri/include/khepri.hrl").

-spec register_on_created(Store :: khepri:store()) -> ok | {error, term()}.
register_on_created(Store) ->
  Filter = feature_filters:when_created(configs),
  PropOpts =
    #{expect_specific_node => false,
      props_to_return =>
        [payload, payload_version, child_list_version, child_list_length, child_names],
      include_root_props => true},
  Id = binary_to_atom(<<"on_config_created">>, utf8),
  khepri:register_trigger(Store, Id, Filter, configs_procs:on_create_key(), PropOpts).

-spec register_on_deleted(Store :: atom()) -> ok | {error, term()}.
register_on_deleted(Store) ->
  Filter = feature_filters:when_deleted(configs),
  PropOpts =
    #{expect_specific_node => false,
      props_to_return =>
        [payload, payload_version, child_list_version, child_list_length, child_names],
      include_root_props => true},
  Id = binary_to_atom(<<"on_config_deleted">>, utf8),
  khepri:register_trigger(Store, Id, Filter, configs_procs:on_delete_key(), PropOpts).

-spec register_on_updated(Store :: atom()) -> ok | {error, term()}.
register_on_updated(Store) ->
  Filter = feature_filters:when_updated(configs),
  PropOpts =
    #{expect_specific_node => false,
      props_to_return =>
        [payload, payload_version, child_list_version, child_list_length, child_names],
      include_root_props => true},
  Id = binary_to_atom(<<"on_config_updated">>, utf8),
  khepri:register_trigger(Store, Id, Filter, configs_procs:on_update_key(), PropOpts).
