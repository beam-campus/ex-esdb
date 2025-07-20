-module(streams).

-include_lib("khepri/include/khepri.hrl").

-export([setup_when_new_event/3]).

-spec setup_when_new_event(Store :: khepri:store(),
                           Id :: string(),
                           Filter :: khepri:filter()) ->
                            ok | {error, term()}.
setup_when_new_event(Store, Id, Filter) ->
  ok = streams_procs:put_on_new_event(Store, Id),
  ok = streams_triggers:register_on_new_event(Store, Id, Filter),
  ok.
