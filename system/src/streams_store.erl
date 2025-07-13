-module(streams_store).

-include_lib("khepri/include/khepri.hrl").

-export([get_event/2]).

-spec get_event(Store :: khepri:store(), Path :: khepri_path:path()) ->
                 {ok, khepri:props()} | {error, term()}.
get_event(Store, Path) ->
  khepri:get(Store, Path).
