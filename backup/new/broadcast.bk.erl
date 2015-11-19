-module (broadcast).
-export ([start_client/1, start_server/0, client_handler/2, server_handler/1]).


server_node() ->
	master@localhost.

start_server() ->
	register(master_pid, spawn(broadcast, server_handler,[])),
	start_broadcast_layers(),
	server_handler([]).

start_client(Username) ->
	io:format("Hello ~w~n", [Username]),
	register(client_pid, spawn(broadcast, client_handler,[[], Username])),
	start_broadcast_layers(),
	cob_handler ! {cob_broadcast, {Username, Message}},
	client_handler([], Username).

start_broadcast_layers() ->
	register(cob_pid, spawn(broadcast, cob_handler,[[]]])),
	register(rb_pid, spawn(broadcast, rb_handler,[[]]])),
	register(beb_pid, spawn(broadcast, beb_handler,[[]]])).
	
send_message(Message) ->
	client_pid ! {client_msg_req, Message}


% client_handler(State) ->

client_handler(State, Username) ->
	receive
		{cob_deliver, {Message, Username}} ->
			io:format("Message from ~w: ~p~n", [Username, Message]);

		{client_msg_req, Message} ->
			cob_pid ! {cob_broadcast, {Message, Username}}
	end.

server_handler(State) ->
	cob_handler ! {cob_broadcast, Username, Message},
	server_handler(State).




cob_handler(State) ->
	receive
		{cob_broadcast, {Message, Username}} ->
			rb_pid ! {rb_broadcast, {History, Message, Username}};
			NewHistory = [Message | History]

		{cob_deliver, _FromRB, {data, From, Msg}} ->
	end.


% Implementation of Eager Reliable Broadcast
erb_handler(State) ->
    receive
        %% old simple
        {subscribe, Pid} ->
            #erb_state{my_up = Ups} = State,
            link(Pid),
            erb_handler(State#erb_state{
                    my_up = sets:add_element(Pid, Ups)});

        %% with From and ack
        {subscribe, From, Pid} = M ->
            link(Pid),
            From ! {ack, self(), M},
            #erb_state{my_up = Ups} = State,
            erb_handler(State#erb_state{
                    my_up = sets:add_element(Pid, Ups)});

        {rb_deliver, {History, Message, Username}} ->


        {rb_broadcast, From, Msg} -> 
            #erb_state{down = D} = State,
            beb_pid ! {broadcast, From, {data, self(), Msg}},
            erb_handler(State);

        %% {deliver, _From_Beb, {data, Self, {{broadcast, From_Up, Msg}, _Seq}}} ->
        {beb_deliver, _From_Beb, {data, From_Up, Msg}} ->
            #erb_state{delivered = Deli, my_up = Ups, down = Down} = State,
            %% Does Msg belongs to delivered
            case lists:filter(fun(N) -> Msg == N end, Deli) of
                [] -> 
                    New_State = State#erb_state{delivered = lists:append([Msg], Deli)},
                    [rb_pid ! {deliver, From_Up, Msg} || Up <- sets:to_list(Ups)],
                    Down ! {broadcast, self(), {data, From_Up, Msg}},
                    erb_handler(New_State);
                _ -> 
                	erb_handler(State)
            end
    end.


% Implementation of Best-effort Broadcast
beb_handler(State) ->
    receive
        {subscribe, Pid} ->
            #beb_state{my_up = Ups} = State,
            link(Pid),
            beb_handler(State#beb_state{
                    my_up = sets:add_element(Pid, Ups)});

        {broadcast, _From, _Msg} = M -> 
            #beb_state{down = D, others = Others} = State,
            [D ! {send, self(), Other, M} || Other <- Others],
            beb_handler(State);

        {deliver, _ , Self, {broadcast, From, Msg}} ->
            #beb_state{my_up = Ups} = State,
            [rb_pid ! {deliver, From, Msg} || Up <- sets:to_list(Ups)],
            beb_handler(State)
    end.

