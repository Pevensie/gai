-module(gai_erlang_test_ffi).
-export([ref_get/1, ref_set/2]).

%% Use process dictionary for simple mutable state in tests
ref_get(Ref) ->
    case get({test_ref, Ref}) of
        undefined -> 0;
        Value -> Value
    end.

ref_set(Ref, Value) ->
    put({test_ref, Ref}, Value),
    nil.
