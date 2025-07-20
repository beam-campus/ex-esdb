-module(tracker_group).

-export([join/3, members/2, group_key/2, leave/3, notify_created/3, notify_deleted/3,
         notify_updated/3]).

-spec group_key(Store :: atom(), Feature :: atom()) -> integer().
group_key(Store, Feature) ->
  erlang:phash2({Store, Feature, trackers}).

created(Feature, Data) ->
  {feature_created, Feature, Data}.

deleted(Feature, Data) ->
  {feature_deleted, Feature, Data}.

updated(Feature, Data) ->
  {feature_updated, Feature, Data}.

-spec join(Store :: atom(), Feature :: atom(), PidOrPids :: pid() | [pid()]) -> ok.
join(Store, Feature, PidOrPids) ->
  Group = group_key(Store, Feature),
  ok = pg:join('Elixir.Phoenix.PubSub', Group, PidOrPids),
  ok.

-spec members(Store :: atom(), Feature :: atom()) -> [pid()].
members(Store, Feature) ->
  Group = group_key(Store, Feature),
  pg:get_members('Elixir.Phoenix.PubSub', Group).

-spec leave(Store :: atom(), Feature :: atom(), PidOrPids :: pid() | [pid()]) -> ok.
leave(Store, Feature, PidOrPids) ->
  Group = group_key(Store, Feature),
  ok = pg:leave('Elixir.Phoenix.PubSub', Group, PidOrPids),
  ok.

-spec notify_created(Store :: atom(), Feature :: atom(), Data :: map()) -> ok.
notify_created(Store, Feature, Data) ->
  Msg = created(Feature, Data),
  Pids = members(Store, Feature),
  lists:foreach(fun(Pid) -> Pid ! Msg end, Pids).

-spec notify_deleted(Store :: atom(), Feature :: atom(), Data :: map()) -> ok.
notify_deleted(Store, Feature, Data) ->
  Msg = deleted(Feature, Data),
  Pids = members(Store, Feature),
  lists:foreach(fun(Pid) -> Pid ! Msg end, Pids).

-spec notify_updated(Store :: atom(), Feature :: atom(), Data :: map()) -> ok.
notify_updated(Store, Feature, Data) ->
  Msg = updated(Feature, Data),
  Pids = members(Store, Feature),
  lists:foreach(fun(Pid) -> Pid ! Msg end, Pids).
