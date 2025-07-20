-module(subscriptions_store).

-include_lib("khepri/include/khepri.hrl").

-export([get_subscription/2, put_subscription/2, delete_subscription/2, key/1,
         update_subscription/2, exists/2]).

get_subscription(Store, Key) when is_binary(Key) ->
  Path = [subscriptions, Key],
  get_subscription(Store, Path);
get_subscription(Store, Path) when is_list(Path) ->
  case khepri:get(Store, Path) of
    {ok, Subscription} ->
      Subscription;
    {error, _Reason} ->
      nil
  end.

key(KeyT) when is_tuple(KeyT) ->
  integer_to_binary(erlang:phash2(KeyT));
key(Subscription) when is_map(Subscription) ->
  #{type := Type,
    selector := Selector,
    subscription_name := SubscriptionName} =
    Subscription,
  key({Type, Selector, SubscriptionName}).

-spec exists(atom(), map()) -> boolean().
exists(Store, Subscription) ->
  Key = key(Subscription),
  case khepri:exists(Store, [subscriptions, Key]) of
    true ->
      true;
    false ->
      false;
    {error, Reason} ->
      io:format("Warning: khepri:exists failed in exists/2 with reason: ~p~n", [Reason]),
      false
  end.

-spec put_subscription(atom(), map()) -> ok.
put_subscription(Store, Subscription) ->
  Key = key(Subscription),
  case khepri:exists(Store, [subscriptions, Key]) of
    true ->
      ok = khepri:update(Store, [subscriptions, Key], Subscription),
      % Request asynchronous persistence
      ok;
    false ->
      ok = khepri:put(Store, [subscriptions, Key], Subscription),
      % Request asynchronous persistence
      ok
  end.

-spec delete_subscription(atom(), map()) -> ok.
delete_subscription(Store, Subscription) ->
  Key = key(Subscription),
  case khepri:exists(Store, [subscriptions, Key]) of
    true ->
      ok = khepri:delete(Store, [subscriptions, Key]),
      % Request asynchronous persistence
      ok;
    false ->
      ok
  end.

-spec update_subscription(atom(), map()) -> ok.
update_subscription(Store, Subscription) ->
  Key = key(Subscription),
  case khepri:exists(Store, [subscriptions, Key]) of
    true ->
      ok = khepri:update(Store, [subscriptions, Key], Subscription),
      % Request asynchronous persistence
      ok;
    false ->
      ok = khepri:put(Store, [subscriptions, Key], Subscription),
      % Request asynchronous persistence
      ok
  end.
