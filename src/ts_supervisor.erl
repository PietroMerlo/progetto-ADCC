
-module(ts_supervisor).

-export([start_link/1, init/1, loop/2]).

start_link(Name) ->
    case global:whereis_name({ts, Name}) of
        undefined ->
            Pid = spawn_link(?MODULE, init, [Name]),
            register(Name, Pid),
            case global:register_name({ts, Name}, Pid) of
                yes -> ok;
                no -> {err, global_registration_failed}
            end;
        _ ->
            {err, already_exists}
    end.

init(Name) ->
    process_flag(trap_exit, true),
    {ok, OwnerPid} = ts_owner:start(Name),
    loop(Name, OwnerPid).

loop(Name, OwnerPid) ->
    receive
       
        {'EXIT', OwnerPid, normal} ->
            ok;

        {'EXIT', OwnerPid, shutdown} ->
            ok;

        {'EXIT', OwnerPid, _Reason} ->
            {ok, NewOwnerPid} = ts_owner:start(Name),
            loop(Name, NewOwnerPid);

        {stop, From} ->
            OwnerPid ! stop,
            global:unregister_name({ts, Name}),
            unregister(Name),
            From ! {reply, ok};

        Msg ->
            OwnerPid ! Msg,
            loop(Name, OwnerPid)
    end.