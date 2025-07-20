-module(emitter_group).

-export([join/3, members/2, broadcast/3, group_key/2, topic/2, emitter_name/2,
         emitter_name/3, persist_emitters/3, setup_emitter_mechanism/4, leave/3,
         retrieve_emitters/2]).

-spec setup_emitter_mechanism(Store :: atom(),
                              Id :: string(),
                              Filter :: map(),
                              PoolSize :: integer()) ->
                               list().
setup_emitter_mechanism(Store, Id, Filter, PoolSize) ->
  ok = streams:setup_when_new_event(Store, Id, Filter),
  Emitters = persist_emitters(Store, Id, PoolSize),
  Emitters.

-spec join(Store :: atom(), Id :: string(), PidOrPids :: pid() | [pid()]) -> ok.
join(Store, Id, PidOrPids) when is_atom(Store) ->
  Group = group_key(Store, Id),
  ok = pg:join('Elixir.Phoenix.PubSub', Group, PidOrPids),
  ok.

-spec leave(Store :: atom(), Id :: string(), PidOrPids :: pid() | [pid()]) -> ok.
leave(Store, Id, PidOrPids) when is_atom(Store) ->
  Group = group_key(Store, Id),
  ok = pg:leave('Elixir.Phoenix.PubSub', Group, PidOrPids),
  ok.

-spec members(Store :: atom(), Id :: string()) -> [pid()].
members(Store, Id) when is_atom(Store) ->
  Group = group_key(Store, Id),
  pg:get_members('Elixir.Phoenix.PubSub', Group).

-spec random_emitter(Emitters :: [pid()]) -> {error, {no_such_group, term()}} | pid().
random_emitter(Emitters) ->
  EmittersTuple = list_to_tuple(Emitters),
  Size = tuple_size(EmittersTuple),
  Random = rand:uniform(Size),
  erlang:element(Random, EmittersTuple).

-spec broadcast(Store :: atom(), Id :: string(), Event :: map()) -> ok | {error, term()}.
broadcast(Store, Id, Event) when is_atom(Store) ->
  Topic = topic(Store, Id),
  Members = members(Store, Id),
  if length(Members) > 0 ->
       EmitterPid = random_emitter(Members),
       Message =
         if node(EmitterPid) =:= node() ->
              forward_to_local_msg(Topic, Event);
            true ->
              broadcast_msg(Topic, Event)
         end,
       EmitterPid ! Message;
     true ->
       logger:warning("No Emitters for [~p]~n", [Topic])
  end.

-spec forward_to_local_msg(Topic :: binary(), Event :: map()) -> tuple().
forward_to_local_msg(Topic, Event) ->
  {forward_to_local, Topic, Event}.

-spec broadcast_msg(Topic :: binary(), Event :: map()) -> tuple().
broadcast_msg(Topic, Event) ->
  {broadcast, Topic, Event}.

group_key(Store, Id) ->
  {Store, Id, emitters}.

-spec topic(Store :: atom(), Id :: string()) -> binary().
topic(Store, <<"$all">>) ->
  iolist_to_binary(io_lib:format("~s:$all", [Store]));
topic(Store, Id) ->
  iolist_to_binary(io_lib:format("~s:~s", [Store, Id])).

-spec emitter_name(Store :: atom(), Id :: string()) -> atom().
emitter_name(Store, Id) ->
  list_to_atom(lists:flatten(
                 io_lib:format("~s_~s_emitter", [Store, Id]))).

-spec emitter_name(Store :: atom(), Id :: string(), Number :: integer()) -> atom().
emitter_name(Store, Id, Number) ->
  list_to_atom(lists:flatten(
                 io_lib:format("~s_~s_emitter_~p", [Store, Id, Number]))).

-spec persist_emitters(Store :: atom(), Id :: string(), PoolSize :: integer()) -> list().
persist_emitters(Store, Id, PoolSize) ->
  % Generate a list of emitter names
  EmitterList = [emitter_name(Store, Id, Number) || Number <- lists:seq(1, PoolSize - 1)],
  Emitters = [emitter_name(Store, Id) | EmitterList],
  Key = group_key(Store, Id),
  ok = persistent_term:put(Key, list_to_tuple(Emitters)),
  Emitters.

-spec retrieve_emitters(Store :: atom(), Id :: string()) -> list().
retrieve_emitters(Store, Id) ->
  Key = group_key(Store, Id),
  EmitterTuple = persistent_term:get(Key),
  tuple_to_list(EmitterTuple).
