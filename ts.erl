-module(ts).
-behaviour(gen_server).

-export([new/1, out/2, in/2, in/3, rd/2, rd/3,
         add_node/2, remove_node/2, nodes/1, stop/1]).

-export([init/1, handle_call/3, handle_cast/2,
         handle_info/2, terminate/2, code_change/3]).

-record(state, {
    name,
    table,
    waiting = [],   % {Pattern, From, Type, Ref}
    nodes = []
}).

%% =========================
%% API
%% =========================

new(Name) ->
    gen_server:start_link({global, Name}, ?MODULE, [Name], []).

out(TS, Tuple) when is_tuple(Tuple) ->
    gen_server:cast({global, TS}, {out, Tuple}).

in(TS, Pattern) ->
    gen_server:call({global, TS}, {in, Pattern}, infinity).

in(TS, Pattern, Timeout) ->
    try gen_server:call({global, TS}, {in, Pattern}, Timeout) of
        Res -> Res
    catch
        exit:{timeout, _} -> {err, timeout}
    end.

rd(TS, Pattern) ->
    gen_server:call({global, TS}, {rd, Pattern}, infinity).

rd(TS, Pattern, Timeout) ->
    try gen_server:call({global, TS}, {rd, Pattern}, Timeout) of
        Res -> Res
    catch
        exit:{timeout, _} -> {err, timeout}
    end.

add_node(TS, Node) ->
    gen_server:call({global, TS}, {add_node, Node}).

remove_node(TS, Node) ->
    gen_server:call({global, TS}, {remove_node, Node}).

nodes(TS) ->
    gen_server:call({global, TS}, nodes).

stop(TS) ->
    gen_server:stop({global, TS}).

%% =========================
%% INIT
%% =========================

init([Name]) ->
    Table = ets:new(Name, [bag, public]),
    {ok, #state{name = Name, table = Table, nodes = []}}.

%% =========================
%% CALLS
%% =========================

handle_call({in, Pattern}, From, State) ->
    case ets:match_object(State#state.table, Pattern) of
        [T | _] ->
            ets:delete_object(State#state.table, T),
            {reply, {ok, T}, State};
        [] ->
            {Pid, _Tag} = From,
            Ref = erlang:monitor(process, Pid),
            {noreply, State#state{
                waiting = [{Pattern, From, in, Ref} | State#state.waiting]
            }}
    end;

handle_call({rd, Pattern}, From, State) ->
    case ets:match_object(State#state.table, Pattern) of
        [T | _] ->
            {reply, {ok, T}, State};
        [] ->
            {Pid, _Tag} = From,
            Ref = erlang:monitor(process, Pid),
            {noreply, State#state{
                waiting = [{Pattern, From, rd, Ref} | State#state.waiting]
            }}
    end;

handle_call({add_node, Node}, _From, State) ->
    erlang:monitor_node(Node, true),
    NewNodes = lists:usort([Node | State#state.nodes]),
    {reply, ok, State#state{nodes = NewNodes}};

handle_call({remove_node, Node}, _From, State) ->
    erlang:monitor_node(Node, false),
    NewNodes = lists:delete(Node, State#state.nodes),
    {reply, ok, State#state{nodes = NewNodes}};

handle_call(nodes, _From, State) ->
    {reply, lists:usort([node() | State#state.nodes]), State}.

%% =========================
%% CAST
%% =========================

handle_cast({out, Tuple}, State) ->
    ets:insert(State#state.table, Tuple),
    NewState = try wake_waiters(Tuple, State)
               catch _:_ -> State
               end,
    {noreply, NewState}.

%% =========================
%% WAITERS
%% =========================

wake_waiters(Tuple, State) ->
    Table = State#state.table,
    {Remaining, _} =
        lists:foldl(
            fun({Pattern, From, Type, Ref}, {Acc, Consumed}) ->
                case matches(Pattern, Tuple) of
                    false ->
                        {[{Pattern, From, Type, Ref} | Acc], Consumed};
                    true ->
                        erlang:demonitor(Ref, [flush]),
                        case Type of
                            in when Consumed =:= false ->
                                ets:delete_object(Table, Tuple),
                                catch gen_server:reply(From, {ok, Tuple}),
                                {Acc, true};
                            rd ->
                                catch gen_server:reply(From, {ok, Tuple}),
                                {Acc, Consumed};
                            _ ->
                                {[{Pattern, From, Type, Ref} | Acc], Consumed}
                        end
                end
            end,
            {[], false},
            State#state.waiting
        ),
    State#state{waiting = Remaining}.

%% =========================
%% MATCHING
%% =========================

matches(Pattern, Tuple) ->
    try
        lists:all(
            fun({P, T}) -> P =:= '_' orelse P =:= T end,
            lists:zip(tuple_to_list(Pattern), tuple_to_list(Tuple))
        )
    catch
        _:_ -> false
    end.

%% =========================
%% INFO
%% =========================

handle_info({'DOWN', Ref, process, _Pid, _Reason}, State) ->
    NewWaiting =
        lists:filter(
            fun({_, _, _, R}) -> R =/= Ref end,
            State#state.waiting
        ),
    {noreply, State#state{waiting = NewWaiting}};


handle_info({nodedown, Node}, State) ->
    case whereis(bench_proc) of
        undefined -> ok;
        Pid -> Pid ! {nodedown_detected, erlang:monotonic_time(millisecond)}
    end,
    NewNodes = lists:delete(Node, State#state.nodes),
    {noreply, State#state{nodes = NewNodes}};

handle_info(_, State) ->
    {noreply, State}.

%% =========================
%% CLEANUP
%% =========================

terminate(_, State) ->
    ets:delete(State#state.table),
    ok.

code_change(_, State, _) ->
    {ok, State}.