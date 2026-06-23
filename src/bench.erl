-module(bench).

-export([
    run/0,
    bench_out/1,
    bench_rd/1,
    bench_in/1,
    bench_recovery/1
]).

-define(TS, tsbench).

run() ->
    io:format("~n--- BENCHMARK START ---~n", []),
    io:format("Compila prima tuple_space, ts_owner, ts_supervisor e il tuo codice con crash.~n", []),
    cleanup(),
    {OutAvg, OutMin, OutMax} = bench_out(1000),
    cleanup(),
    {RdAvg, RdMin, RdMax} = bench_rd(1000),
    cleanup(),
    {InAvg, InMin, InMax} = bench_in(1000),
    cleanup(),
    {RecAvg, RecMin, RecMax} = bench_recovery(1000),
    cleanup(),
    io:format("~n--- RISULTATI FINALI ---~n", []),
    io:format("OUT average: ~p us | min: ~p us | max: ~p us~n", [OutAvg, OutMin, OutMax]),
    io:format("RD  average: ~p us | min: ~p us | max: ~p us~n", [RdAvg, RdMin, RdMax]),
    io:format("IN  average: ~p us | min: ~p us | max: ~p us~n", [InAvg, InMin, InMax]),
    io:format("REC average: ~p us | min: ~p us | max: ~p us~n", [RecAvg, RecMin, RecMax]),
    io:format("--- BENCHMARK END ---~n", []),
    ok.

bench_out(N) ->
    ensure_ts(),
    Times = [measure_out(I) || I <- lists:seq(1, N)],
    stats(Times).

bench_rd(N) ->
    ensure_ts(),
    Times = [measure_rd(I) || I <- lists:seq(1, N)],
    stats(Times).

bench_in(N) ->
    ensure_ts(),
    Times = [measure_in(I) || I <- lists:seq(1, N)],
    stats(Times).

bench_recovery(N) ->
    Times = [measure_recovery(I) || I <- lists:seq(1, N)],
    stats(Times).

measure_out(I) ->
    Tuple = {out_test, I},
    T1 = erlang:monotonic_time(microsecond),
    {ok, _} = tuple_space:out(?TS, Tuple),
    T2 = erlang:monotonic_time(microsecond),
    {ok, Tuple} = tuple_space:in(?TS, Tuple),
    T2 - T1.

measure_rd(I) ->
    Tuple = {rd_test, I},
    {ok, _} = tuple_space:out(?TS, Tuple),
    T1 = erlang:monotonic_time(microsecond),
    {ok, Tuple} = tuple_space:rd(?TS, Tuple),
    T2 = erlang:monotonic_time(microsecond),
    {ok, Tuple} = tuple_space:in(?TS, Tuple),
    T2 - T1.

measure_in(I) ->
    Tuple = {in_test, I},
    {ok, _} = tuple_space:out(?TS, Tuple),
    T1 = erlang:monotonic_time(microsecond),
    {ok, Tuple} = tuple_space:in(?TS, Tuple),
    T2 = erlang:monotonic_time(microsecond),
    T2 - T1.

measure_recovery(I) ->
    Name = recovery_name(I),
    _ = catch tuple_space:stop(Name),
    case tuple_space:new(Name) of
        ok -> ok;
        {err, already_exists} -> ok
    end,
    {ok, _} = tuple_space:out(Name, {probe, I}),
    T1 = erlang:monotonic_time(microsecond),
    crash_owner(Name),
    wait_until_responsive(Name, {probe, I}),
    T2 = erlang:monotonic_time(microsecond),
    _ = catch tuple_space:stop(Name),
    T2 - T1.

stats(Times) ->
    Sum = lists:sum(Times),
    Avg = Sum / length(Times),
    Min = lists:min(Times),
    Max = lists:max(Times),
    {Avg, Min, Max}.

ensure_ts() ->
    case catch tuple_space:new(?TS) of
        ok ->
            ok;
        {err, already_exists} ->
            ok;
        _ ->
            ok
    end.

cleanup() ->
    _ = catch tuple_space:stop(?TS),
    ok.


recovery_name(I) ->
    list_to_atom("tsrec_" ++ integer_to_list(I)).

wait_until_responsive(Name, Tuple) ->
    case catch tuple_space:rd(Name, Tuple, 10) of
        {ok, Tuple} ->
            ok;
        {err, timeout} ->
            timer:sleep(1),
            wait_until_responsive(Name, Tuple);
        {'EXIT', _} ->
            timer:sleep(1),
            wait_until_responsive(Name, Tuple);
        _ ->
            timer:sleep(1),
            wait_until_responsive(Name, Tuple)
    end.

crash_owner(Name) ->
    Dest =
        case whereis(Name) of
            undefined ->
                global:whereis_name({ts, Name});
            Pid ->
                Pid
        end,
    Dest ! {self(), crash},
    receive
        {reply, crashing} ->
            ok
    after 100 ->
        ok
    end.