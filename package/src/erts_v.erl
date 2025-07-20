-module(erts_v).

-export([parse_transform/2]).

parse_transform(AST, _Opts) ->
  io:format("~p~n", [AST]).
