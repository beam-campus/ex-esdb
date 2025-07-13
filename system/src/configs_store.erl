-module(configs_store).

-include_lib("khepri/include/khepri.hrl").

-export([get_config/2, put_config/2, delete_config/2, key/1,
         update_config/2, exists/2]).

get_config(Store, Key) when is_binary(Key) ->
  Path = [configs, Key],
  get_config(Store, Path);
get_config(Store, Path) when is_list(Path) ->
  case khepri:get(Store, Path) of
    {ok, Config} ->
      Config;
    {error, _Reason} ->
      nil
  end.

key(KeyT) when is_tuple(KeyT) ->
  integer_to_binary(erlang:phash2(KeyT));
key(Config) when is_map(Config) ->
  #{type := Type,
    selector := Selector,
    config_name := ConfigName} =
    Config,
  key({Type, Selector, ConfigName}).

-spec exists(atom(), map()) -> boolean().
exists(Store, Config) ->
  Key = key(Config),
  khepri:exists(Store, [configs, Key]).

-spec put_config(atom(), map()) -> ok.
put_config(Store, Config) ->
  Key = key(Config),
  case khepri:exists(Store, [configs, Key]) of
    true ->
      ok = khepri:update(Store, [configs, Key], Config),
      ok;
    false ->
      ok = khepri:put(Store, [configs, Key], Config),
      ok
  end.

-spec delete_config(atom(), map()) -> ok.
delete_config(Store, Config) ->
  Key = key(Config),
  case khepri:exists(Store, [configs, Key]) of
    true ->
      ok = khepri:delete(Store, [configs, Key]),
      ok;
    false ->
      ok
  end.

-spec update_config(atom(), map()) -> ok.
update_config(Store, Config) ->
  Key = key(Config),
  case khepri:exists(Store, [configs, Key]) of
    true ->
      ok = khepri:update(Store, [configs, Key], Config),
      ok;
    false ->
      ok = khepri:put(Store, [configs, Key], Config),
      ok
  end.
