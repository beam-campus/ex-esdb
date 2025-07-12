-module(feature_filters).

-export([when_created/1, when_deleted/1, when_updated/1]).

-include_lib("khepri/include/khepri.hrl").

-spec when_created(Feature :: atom()) -> khepri_evf:event_filter().
when_created(Feature) ->
  khepri_evf:tree([Feature, #if_path_matches{regex = any}], #{on_actions => [create]}).

-spec when_deleted(Feature :: atom()) -> khepri_evf:event_filter().
when_deleted(Feature) ->
  khepri_evf:tree([Feature, #if_path_matches{regex = any}], #{on_actions => [delete]}).

-spec when_updated(Feature :: atom()) -> khepri_evf:event_filter().
when_updated(Feature) ->
  khepri_evf:tree([Feature, #if_path_matches{regex = any}], #{on_actions => [update]}).
