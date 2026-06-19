-module(tuple_space).

-export([
    new/1, stop/1,
    out/2,
    in/2, in/3,
    rd/2, rd/3,
    addNode/2, removeNode/2, nodes/1
]).

new(Name) ->
    ts_supervisor:start_link(Name).

dest(TS) ->
    case whereis(TS) of
        undefined ->
            case global:whereis_name({ts, TS}) of
                undefined ->
                    exit({unknown_tuple_space, TS});
                Pid ->
                    Pid
            end;
        Pid ->
            Pid
    end.

stop(TS) ->
    Dest = dest(TS),
    Dest ! {stop, self()},
    receive
        {reply, Reply} -> Reply
    after 5000 ->
        {err, timeout}
    end.

out(TS, Tuple) ->
    Ref = make_ref(),
    Dest = dest(TS),
    Dest ! {self(), {out, Ref, Tuple}},
    receive
        {Ref, Reply} -> Reply
    after 5000 ->
        {err, timeout}
    end.

in(TS, Pattern) ->
    Ref = make_ref(),
    Dest = dest(TS),
    Dest ! {self(), {in, Ref, Pattern}},
    receive
        {Ref, Reply} -> Reply
    end.

in(TS, Pattern, Timeout) ->
    Ref = make_ref(),
    Dest = dest(TS),
    Dest ! {self(), {in, Ref, Pattern}},
    receive
        {Ref, Reply} -> Reply
    after Timeout ->
        Dest ! {cancel, self(), Ref},
        {err, timeout}
    end.

rd(TS, Pattern) ->
    Ref = make_ref(),
    Dest = dest(TS),
    Dest ! {self(), {rd, Ref, Pattern}},
    receive
        {Ref, Reply} -> Reply
    end.

rd(TS, Pattern, Timeout) ->
    Ref = make_ref(),
    Dest = dest(TS),
    Dest ! {self(), {rd, Ref, Pattern}},
    receive
        {Ref, Reply} -> Reply
    after Timeout ->
        Dest ! {cancel, self(), Ref},
        {err, timeout}
    end.

addNode(TS, Node) ->
    Ref = make_ref(),
    Dest = dest(TS),
    Dest ! {self(), {add_node, Ref, Node}},
    receive
        {Ref, Reply} -> Reply
    after 5000 ->
        {err, timeout}
    end.

removeNode(TS, Node) ->
    Ref = make_ref(),
    Dest = dest(TS),
    Dest ! {self(), {remove_node, Ref, Node}},
    receive
        {Ref, Reply} -> Reply
    after 5000 ->
        {err, timeout}
    end.

nodes(TS) ->
    Ref = make_ref(),
    Dest = dest(TS),
    Dest ! {self(), {nodes, Ref}},
    receive
        {Ref, Reply} -> Reply
    after 5000 ->
        {err, timeout}
    end.