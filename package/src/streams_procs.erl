-module(streams_procs).

-include_lib("khepri/include/khepri.hrl").

-export([put_on_new_event/2, get_on_new_event/2]).

on_new_event(Topic) ->
  [procs, on_new_event, Topic].

-spec get_on_new_event(Store :: khepri:store(), Id :: string()) -> ok | {error, term()}.
get_on_new_event(Store, Id) when is_atom(Store) ->
  Topic = emitter_group:topic(Store, Id),
  khepri:get(Store, on_new_event(Topic)).

-spec put_on_new_event(Store :: khepri:store(), Id :: string()) -> ok | {error, term()}.
put_on_new_event(Store, Id) when is_atom(Store) ->
  Topic = emitter_group:topic(Store, Id),
  case khepri:exists(Store, on_new_event(Topic)) of
    true ->
      ok;
    false ->
      ok =
        khepri:put(Store,
                   on_new_event(Topic),
                   fun(Props) ->
                      case maps:get(path, Props, undefined) of
                        undefined -> ok;
                        Path ->
                          case streams_store:get_event(Store, Path) of
                            {ok, undefined} -> ok;
                            {ok, Event} ->
                              emitter_group:broadcast(Store, Id, Event),
                              ok;
                            {error, Reason} ->
                              io:format("Broadcasting failed for path ~p to ~p ~n Reason: ~p~n",
                                        [Path, Topic, Reason]),
                              ok
                          end
                      end
                   end),
      % Request asynchronous persistence
      ok
  end.
