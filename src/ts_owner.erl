-module(ts_owner).

-export([
    start/1,
    init/1,
    loop/5
]).

start(Name) ->
    Pid = spawn_link(?MODULE, init, [Name]),
    {ok, Pid}.

init(Name) ->
    FileName = atom_to_list(Name) ++ ".dets",
    {ok, Tab} = dets:open_file(Name, [
        {file, FileName},
        {type, set},
        {auto_save, 1000},
        {repair, true}
    ]),
    Tuples = load_tuples(Tab),
    Nodes0 = load_nodes(Tab),
    Nodes = case lists:member(node(), Nodes0) of
        true -> Nodes0;
        false -> [node() | Nodes0]
    end,
    ts_owner:loop(Name, Tab, Tuples, Nodes, []).

loop(Name, Tab, Tuples, Nodes, Waiting) ->
    receive
        {cancel, Pid, Ref} ->
            NewWaiting = lists:filter(
                fun({WPid, WRef, _, _}) -> not (WPid == Pid andalso WRef == Ref) end,
                Waiting
            ),
            ts_owner:loop(Name, Tab, Tuples, Nodes, NewWaiting);

        {From, {out, Ref, Tuple}} ->
            case allowed(From, Nodes) of
                true ->
                    {NewTuples, NewWaiting} = handle_out(Tuple, Tuples, Waiting),
                    save_tuples(Tab, NewTuples),
                    From ! {Ref, {ok, Tuple}},
                    ts_owner:loop(Name, Tab, NewTuples, Nodes, NewWaiting);
                false ->
                    From ! {Ref, {err, unauthorized}},
                    ts_owner:loop(Name, Tab, Tuples, Nodes, Waiting)
            end;

        {From, {in, Ref, Pattern}} ->
            case allowed(From, Nodes) of
                true ->
                    case take_first_match(Pattern, Tuples) of
                        {ok, Tuple, Rest} ->
                            save_tuples(Tab, Rest),
                            From ! {Ref, {ok, Tuple}},
                            ts_owner:loop(Name, Tab, Rest, Nodes, Waiting);
                        not_found ->
                            NewWaiting = Waiting ++ [{From, Ref, in, Pattern}],
                            ts_owner:loop(Name, Tab, Tuples, Nodes, NewWaiting)
                    end;
                false ->
                    From ! {Ref, {err, unauthorized}},
                    ts_owner:loop(Name, Tab, Tuples, Nodes, Waiting)
            end;

        {From, {rd, Ref, Pattern}} ->
            case allowed(From, Nodes) of
                true ->
                    case read_first_match(Pattern, Tuples) of
                        {ok, Tuple} ->
                            From ! {Ref, {ok, Tuple}},
                            ts_owner:loop(Name, Tab, Tuples, Nodes, Waiting);
                        not_found ->
                            NewWaiting = Waiting ++ [{From, Ref, rd, Pattern}],
                            ts_owner:loop(Name, Tab, Tuples, Nodes, NewWaiting)
                    end;
                false ->
                    From ! {Ref, {err, unauthorized}},
                    ts_owner:loop(Name, Tab, Tuples, Nodes, Waiting)
            end;

        {From, {add_node, Ref, Node}} ->
            case allowed(From, Nodes) of
                true ->
                    NewNodes =
                        case lists:member(Node, Nodes) of
                            true -> Nodes;
                            false -> Nodes ++ [Node]
                        end,
                    save_nodes(Tab, NewNodes),
                    From ! {Ref, ok},
                    ts_owner:loop(Name, Tab, Tuples, NewNodes, Waiting);
                false ->
                    From ! {Ref, {err, unauthorized}},
                    ts_owner:loop(Name, Tab, Tuples, Nodes, Waiting)
            end;

        {From, {remove_node, Ref, Node}} ->
            case allowed(From, Nodes) of
                true ->
                    NewNodes = lists:filter(fun(X) -> X /= Node end, Nodes),
                    save_nodes(Tab, NewNodes),
                    From ! {Ref, ok},
                    ts_owner:loop(Name, Tab, Tuples, NewNodes, Waiting);
                false ->
                    From ! {Ref, {err, unauthorized}},
                    ts_owner:loop(Name, Tab, Tuples, Nodes, Waiting)
            end;

        {From, {nodes, Ref}} ->
            case allowed(From, Nodes) of
                true ->
                    From ! {Ref, Nodes},
                    ts_owner:loop(Name, Tab, Tuples, Nodes, Waiting);
                false ->
                    From ! {Ref, {err, unauthorized}},
                    ts_owner:loop(Name, Tab, Tuples, Nodes, Waiting)
            end;

        stop ->
            dets:close(Tab),
            ok;

        _Msg ->
            ts_owner:loop(Name, Tab, Tuples, Nodes, Waiting)
    end.

handle_out(Tuple, Tuples, Waiting) ->
    case serve_one_in(Tuple, Waiting) of
        {served, Waiting1} ->
            Waiting2 = serve_all_rd(Tuple, Waiting1),
            {Tuples, Waiting2};
        not_served ->
            Waiting2 = serve_all_rd(Tuple, Waiting),
            {Tuples ++ [Tuple], Waiting2}
    end.

serve_one_in(_Tuple, []) ->
    not_served;

serve_one_in(Tuple, [{Pid, Ref, in, Pattern} | T]) ->
    case match(Pattern, Tuple) of
        true ->
            Pid ! {Ref, {ok, Tuple}},
            {served, T};
        false ->
            case serve_one_in(Tuple, T) of
                not_served -> not_served;
                {served, Rest} -> {served, [{Pid, Ref, in, Pattern} | Rest]}
            end
    end;

serve_one_in(Tuple, [H | T]) ->
    case serve_one_in(Tuple, T) of
        not_served -> not_served;
        {served, Rest} -> {served, [H | Rest]}
    end.

serve_all_rd(_Tuple, []) ->
    [];

serve_all_rd(Tuple, [{Pid, Ref, rd, Pattern} | T]) ->
    case match(Pattern, Tuple) of
        true ->
            Pid ! {Ref, {ok, Tuple}},
            serve_all_rd(Tuple, T);
        false ->
            [{Pid, Ref, rd, Pattern} | serve_all_rd(Tuple, T)]
    end;

serve_all_rd(Tuple, [H | T]) ->
    [H | serve_all_rd(Tuple, T)].

read_first_match(_Pattern, []) ->
    not_found;

read_first_match(Pattern, [H | T]) ->
    case match(Pattern, H) of
        true -> {ok, H};
        false -> read_first_match(Pattern, T)
    end.

take_first_match(_Pattern, []) ->
    not_found;

take_first_match(Pattern, [H | T]) ->
    case match(Pattern, H) of
        true -> {ok, H, T};
        false ->
            case take_first_match(Pattern, T) of
                not_found -> not_found;
                {ok, Tuple, Rest} -> {ok, Tuple, [H | Rest]}
            end
    end.

match(Pattern, Tuple)
when is_tuple(Pattern), is_tuple(Tuple), tuple_size(Pattern) == tuple_size(Tuple) ->
    match_list(tuple_to_list(Pattern), tuple_to_list(Tuple));

match(_, _) ->
    false.

match_list([], []) ->
    true;

match_list(['_' | PT], [_ | TT]) ->
    match_list(PT, TT);

match_list([P | PT], [T | TT]) when P == T ->
    match_list(PT, TT);

match_list(_, _) ->
    false.

load_tuples(Tab) ->
    case dets:lookup(Tab, tuples) of
        [{tuples, L}] -> L;
        [] -> []
    end.

load_nodes(Tab) ->
    case dets:lookup(Tab, nodes) of
        [{nodes, L}] -> L;
        [] -> []
    end.

save_tuples(Tab, Tuples) ->
    dets:insert(Tab, {tuples, Tuples}),
    dets:sync(Tab).

save_nodes(Tab, Nodes) ->
    dets:insert(Tab, {nodes, Nodes}),
    dets:sync(Tab).

allowed(From, Nodes) ->
    lists:member(node(From), Nodes).