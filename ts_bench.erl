-module(ts_bench).
-export([run/0, bench_out/0, bench_in/0, bench_rd/0, bench_recovery/0]).

%% =========================
%% RESET HELPER
%% =========================
reset() ->
    catch ts:stop(bench_ts),
    ts:new(bench_ts).

%% =========================
%% RUN ALL
%% =========================
run() ->
    io:format("=== Tuple Space Benchmarks ===~n"),

    reset(),
    bench_out(),

    reset(),
    bench_rd(),

    reset(),
    bench_in(),

    io:format("=== Done ===~n").

%% =========================
%% OUT
%% measures end-to-end completion (dispatch + processing)
%% =========================
bench_out() ->
    N = 10000,
    T1 = erlang:monotonic_time(microsecond),

    lists:foreach(
        fun(I) -> ts:out(bench_ts, {I, hello}) end,
        lists:seq(1, N)
    ),

    %% barrier: ensure all messages processed
    ts:rd(bench_ts, {N, '_'}),

    T2 = erlang:monotonic_time(microsecond),
    io:format("out/2 avg (end-to-end): ~.2f us~n", [(T2 - T1) / N]).

%% =========================
%% RD
%% prefill then measure read latency
%% =========================
bench_rd() ->
    N = 10000,

    lists:foreach(
        fun(I) -> ts:out(bench_ts, {I, hello}) end,
        lists:seq(1, N)
    ),

    %% ensure all inserted before measuring
    ts:rd(bench_ts, {N, '_'}),

    T1 = erlang:monotonic_time(microsecond),

    lists:foreach(
        fun(I) -> ts:rd(bench_ts, {I, '_'}) end,
        lists:seq(1, N)
    ),

    T2 = erlang:monotonic_time(microsecond),
    io:format("rd/2 avg: ~.2f us~n", [(T2 - T1) / N]).

%% =========================
%% IN
%% prefill then measure consume latency
%% =========================
bench_in() ->
    N = 10000,

    lists:foreach(
        fun(I) -> ts:out(bench_ts, {I, hello}) end,
        lists:seq(1, N)
    ),

    %% ensure all inserted before measuring
    ts:rd(bench_ts, {N, '_'}),

    T1 = erlang:monotonic_time(microsecond),

    lists:foreach(
        fun(I) -> ts:in(bench_ts, {I, '_'}) end,
        lists:seq(1, N)
    ),

    T2 = erlang:monotonic_time(microsecond),
    io:format("in/2 avg: ~.2f us~n", [(T2 - T1) / N]).

%% =========================
%% RECOVERY
%% =========================
bench_recovery() ->
    net_kernel:set_net_ticktime(2),
    catch unregister(bench_proc),
    register(bench_proc, self()),

    RemoteNode = 'client1@Selssabils-MacBook',
    io:format("Monitoring node: ~p~n", [RemoteNode]),

    reset(),
    ts:add_node(bench_ts, RemoteNode),

    case net_adm:ping(RemoteNode) of
        pong ->
            io:format("Node connected. Kill client1 now...~n"),
            T1 = erlang:monotonic_time(millisecond),
            receive
                {nodedown_detected, T2} ->
                    io:format("Recovery time: ~p ms~n", [T2 - T1])
            after 30000 ->
                io:format("Timeout: no nodedown received~n")
            end;
        pang ->
            io:format("ERROR: client1 not connected.~n"),
            io:format("Run net_adm:ping(client1) first.~n")
    end.