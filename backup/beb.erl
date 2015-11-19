-module (beb).
-export ([function/arity]).

% @doc best effort broadcast abstraction
% @author bernard paulus
% @author martin trigaux

-module(beb).
-import(spawn_utils, [spawn_multiple_on_top/2]).
-export([start/1]).

% @type beb_state() = #beb_state{documentation = code}
-record(beb_state, {
        my_up = sets:new(),
        others = [],
        down = none}).

start(Downs) when is_pid(hd(Downs)) ->
    spawn_multiple_on_top(Downs, [fun init/2 || 
            _ <- lists:seq(1,length(Downs))]);

start(Nodes) when is_atom(hd(Nodes)) ->
    start(link:perfect_link(Nodes));

start([]) -> [].


% @spec (Others :: [pid()], Down :: pid()) -> void
% @doc initializes the beb process
init(Others, Down) ->
    Down ! {subscribe, self()},
    beb_loop(#beb_state{others = Others, down = Down}).


% @spec (beb_state()) -> void
% @doc deals with messages {subscribe, Pid, Seq} and 
% {broadcast, From, Seq_Msg, Msg}.
beb_loop(State) ->
    Self = self(),
    receive
        {subscribe, Pid} ->
            #beb_state{my_up = Ups} = State,
            link(Pid),
            beb_loop(State#beb_state{
                    my_up = sets:add_element(Pid, Ups)});

        {broadcast, _From, _Msg} = M -> 
            #beb_state{down = D, others = Others} = State,
            [D ! {send, self(), Other, M} || Other <- Others],
            beb_loop(State);

        {deliver, _ , Self, {broadcast, From, Msg}} ->
            #beb_state{my_up = Ups} = State,
            [Up ! {deliver, From, Msg} || Up <- sets:to_list(Ups)],
            beb_loop(State)
    end.