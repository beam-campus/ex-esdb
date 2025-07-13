-module(configs_procs).

-include_lib("khepri/include/khepri.hrl").

-export([put_on_create_func/1, put_on_delete_func/1, on_create_key/0, on_delete_key/0,
         put_on_update_func/1, on_update_key/0]).

on_create_key() ->
  [procs, configs, on_create].

on_delete_key() ->
  [procs, configs, on_delete].

on_update_key() ->
  [procs, configs, on_update].

put_on_create_func(Store) ->
  case khepri:exists(Store, on_create_key()) of
    true ->
      ok;
    false ->
      ok =
        khepri:put(Store,
                   on_create_key(),
                   fun(Props) ->
                      case maps:get(path, Props, undefined) of
                        undefined -> ok;
                        Path ->
                          case configs_store:get_config(Store, Path) of
                            nil -> ok;
                            Config ->
                              tracker_group:notify_created(Store, configs, Config),
                              ok
                          end
                      end
                   end),
      ok
  end.

put_on_update_func(Store) ->
  case khepri:exists(Store, on_update_key()) of
    true ->
      ok;
    false ->
      ok =
        khepri:put(Store,
                   on_update_key(),
                   fun(Props) ->
                      case maps:get(path, Props, undefined) of
                        undefined -> ok;
                        Path ->
                          case configs_store:get_config(Store, Path) of
                            nil -> ok;
                            Config ->
                              tracker_group:notify_updated(Store, configs, Config),
                              ok
                          end
                      end
                   end),
      ok
  end.

put_on_delete_func(Store) ->
  case khepri:exists(Store, on_delete_key()) of
    true ->
      ok;
    false ->
      ok =
        khepri:put(Store,
                   on_delete_key(),
                   fun(Props) ->
                      case maps:get(path, Props, undefined) of
                        undefined -> ok;
                        Path ->
                          case configs_store:get_config(Store, Path) of
                            nil -> ok;
                            Config ->
                              tracker_group:notify_deleted(Store, configs, Config),
                              ok
                          end
                      end
                   end),
      ok
  end.
