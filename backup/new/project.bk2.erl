-module (broadcast).
-export ([start_client/1, client_handler/2, 
			cob_handler/1, rb_handler/1, beb_handler/1,
			send_message/1, create_group/2, join_group/1, leave_group/1, broadcast_group/2
			% start_server/0, server_handler/1,
		]).


server_node() ->
	server@localhost.

% start_server() ->
% 	register(master_pid, spawn(broadcast, server_handler,[])),
% 	start_broadcast_layers(),
% 	server_handler([]).

% server_handler(State) ->
% 	% cob_handler ! {cob_broadcast, Username, Message},
% 	server_handler(State)

start_client(Username) ->
	% connect to the central node
	net_kernel:connect_node(server_node()),
    case whereis(client_pid) of 
        undefined ->
            register(client_pid, spawn(broadcast, client_handler,[{[]}, Username])),
            start_broadcast_layers(),
            io:format("Hello ~w~n", [Username]);
        _ -> 
        	io:format("You have already logged on this node!")
    end.
	
% cob_handler ! {cob_broadcast, {Username, Message}},

start_broadcast_layers() ->
	register(cob_pid, spawn(broadcast, cob_handler,[{[],[]}])),
	register(rb_pid, spawn(broadcast, rb_handler,[{[]}])),
	register(beb_pid, spawn(broadcast, beb_handler,[[]])).
	
send_message(Message) ->
	client_pid ! {msg_send_req, Message}.

create_group(GroupName, Description) ->
	client_pid ! {group_create_req, GroupName, Description}.

join_group(GroupName) ->
	client_pid ! {group_join_req, GroupName}.

leave_group(GroupName) ->
	client_pid ! {group_leave_req, GroupName}.

broadcast_group(GroupName, Message) ->
	client_pid ! {msg_send_group_req, GroupName, Message}.



%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% APPLICATION LAYER %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

% client_handler(State) ->
%	pass.
% State = {GroupList}; GroupList = [Group1, Group2, ..]
% Group = {Name, Desc, [{Member1, node1}, {Member2, Node2}..]}
client_handler(State, Username) ->
	GroupList = erlang:element(1, State),
	receive
		{cob_deliver, {_Message, _Username}} ->
			case _Message of
				{regular_msg, Data} ->
					client_pid ! {msg_send_ind, Data, _Username},
					client_handler(State, Username);
				{group_info, Data} ->
					client_pid ! {group_create_ind, Data},
					client_handler(State, Username);
				{group_bc, Data, _GroupNodes, GroupName} ->
					client_pid ! {msg_send_group_ind, Data, _Username, GroupName},
					client_handler(State, Username);
				_ ->
					io:format("[~w]: ~p~n", [_Username, _Message]),
					client_handler(State, Username)
			end;			

		{msg_send_req, _Message} ->
			%io:format("Message from ~w: ~p~n", [Username, _Message]),
			Message = {regular_msg, _Message},

			cob_pid ! {cob_broadcast, {Message, Username}},
			client_handler(State, Username);

		{msg_send_ind, _Message, _Username} ->
			io:format("[~w]: ~p~n", [_Username, _Message]),			
			client_handler(State, Username);

		{group_create_req, GroupName, Description} ->
			%GroupList = erlang:element(1, State),
			Group = {GroupName, Description, [{Username, node()}]},
			UpdatedGroupList = [Group | GroupList],
			UpdatedState = erlang:setelement(1, State, UpdatedGroupList),
			Message = {group_info, UpdatedGroupList},

			cob_pid ! {cob_broadcast, {Message, Username}},
			client_handler(UpdatedState, Username);

		{group_create_ind, _GroupList} ->			
			UpdatedState = erlang:setelement(1, State, _GroupList),
			io:format("Updated conversation group list: ~p~n", [_GroupList]),
			client_handler(UpdatedState, Username);

		{group_join_req, _GroupName} ->
			%should sync the latest list first
			case lists:keysearch(_GroupName, 1, GroupList) of
                false ->
                    no_such_group,
                    client_handler(State, Username);
                {value, {Name, Desc, MemberList}} ->
                    UpdatedMemberList = [{Username, node()} | MemberList],
                    UpdatedGroup = {Name, Desc, UpdatedMemberList},
                    UpdatedGroupList = lists:keyreplace(Name, 1, GroupList, UpdatedGroup),
                    UpdatedState = erlang:setelement(1, State, UpdatedGroupList),
					Message = {group_info, UpdatedGroupList},

					cob_pid ! {cob_broadcast, {Message, Username}},
					client_handler(UpdatedState, Username)
            end;

		{group_leave_req, _GroupName} ->
			%should sync the latest list first
			case lists:keysearch(_GroupName, 1, GroupList) of
                false ->
                    group_not_found,
                    client_handler(State, Username);
                {value, {Name, Desc, MemberList}} ->
                    UpdatedMemberList = lists:delete({Username, node()}, MemberList),
                    UpdatedGroup = {Name, Desc, UpdatedMemberList},
                    UpdatedGroupList = lists:keyreplace(Name, 1, GroupList, UpdatedGroup),
                    UpdatedState = erlang:setelement(1, State, UpdatedGroupList),
					Message = {group_info, UpdatedGroupList},

					cob_pid ! {cob_broadcast, {Message, Username}},
					client_handler(UpdatedState, Username)
            end;

        {msg_send_group_req, _GroupName, _Message} ->
         	% check if user is in grop=up
         	case lists:keysearch(_GroupName, 1, GroupList) of
                false ->
                    group_not_found,
                    client_handler(State, Username);
                {value, {_Name, _Desc, MemberList}} ->
                	GroupNode = lists:flatmap(fun({_, Node}) -> [Node] end, MemberList),
            		Message = {group_bc, _Message, GroupNode, _Name},
					cob_pid ! {cob_broadcast, {Message, Username}},
					client_handler(State, Username)
            end;

        {msg_send_group_ind, Data, _Username, GroupName} ->
        	io:format("[~w] via [~w]: ~p~n", [_Username, GroupName, Data]),
        	client_handler(State, Username)         	

	end.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%  BROADCAST ALGORITHM LAYER %%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

%%%%%%%%%%%%%%%%%%%%%%  CAUSAL RELIABLE ORDER BROADCAST %%%%%%%%%%%%%%%%%%%%%%%%%%

% State = {Delivered, History} = {{[{Message}], [{Message, Username}]}
cob_handler(State) ->	
	Delivered = erlang:element(1, State),
	History = erlang:element(2, State),
	receive
		{cob_broadcast, {Message, Username}} ->		
			% io:format("i am here"),
			% pass down to RB layer
			%io:format("COB Msg: [~p] from [~w]~n", [Message, Username]),
			rb_pid ! {rb_broadcast, {History, Message, Username}},
			% append new msg to history, from right to left
			% for the sake of retrieving
			NewHistory = lists:append(History, [{Message, Username}]),
			cob_handler({Delivered, NewHistory});

		{rb_deliver, {_History, _Message, _Username}} ->
			% if the message is not yet delivered
			%io:format("COB Msg: [~p] from [~w]~n", [_Message, _Username]),
			case lists:keymember(_Message, 1, Delivered) of
				false ->
					% run through the history of message
					lists:foreach(	
						fun(X) -> % list of {Message, Username}
							%if any msg is not delivered yet
							HistoryMsg = erlang:element(1, X),
							case lists:keymember(HistoryMsg, 1, Delivered) of
								false -> % if not
									% deliver it to upper layer (user)
									client_pid ! {cob_deliver, HistoryMsg},
									% update delivered list
									NewDelivered = [{erlang:element(1, HistoryMsg)} | Delivered],
									% update the history message list
									NewHistory = lists:append(History, [HistoryMsg]),
									% update state
									cob_handler({NewDelivered, NewHistory});
								true ->
									cob_handler(State)
							end							
						end, _History),
					% deliver the current message
					%io:format("i am here"),
					client_pid ! {cob_deliver, {_Message, _Username}},
					% add it to the delivered list and history
					UpdatedDelivered = [{_Message} | Delivered],
					UpdatedHistory = lists:append(History, [{_Message, _Username}]),
					% updated the global state
					cob_handler({UpdatedDelivered, UpdatedHistory});					
				true ->
					cob_handler(State)
			end
	end.

%%%%%%%%%%%%%%%%%%%%%%%%%%  RELIABLE BROADCAST %%%%%%%%%%%%%%%%%%%%%%%%%%%%

% Implementation of Eager Reliable Broadcast
% State = {[{Delivered_Msg}]}
rb_handler(State) ->
    receive
        {rb_broadcast, {_History, Message, Username}} -> 
            % #erb_state{down = D} = State,
            %io:format("RB Msg: [~p] from [~w]~n", [Message, Username]),
            % beb_pid ! {broadcast, From, {data, self(), Msg}},
            beb_pid ! {beb_broadcast, {Message, Username}},
            rb_handler(State);

        %% {deliver, _From_Beb, {data, Self, {{broadcast, From_Up, Msg}, _Seq}}} ->
        {beb_deliver, {Message, Username}} ->
            % #erb_state{delivered = Deli, my_up = Ups, down = Down} = State,
            %% Does Msg belongs to delivered
           % io:format("RB Msg: [~p] from [~w]~n", [Message, Username]),
            DeliveredMsg = erlang:element(1, State),
            % case lists:filter(fun(M) -> Message == M end, DeliveredMsg) of
            %     [] -> 
           	case lists:keymember(Message, 1, DeliveredMsg) of
           		false ->          	
                    UpdatedDeliveredMsg = [{Message} | DeliveredMsg],
                    History = [],
                    cob_pid ! {rb_deliver, {History, Message, Username}},
                    beb_pid ! {beb_broadcast, {Message, Username}},
                    rb_handler({UpdatedDeliveredMsg});
                true -> 
                	rb_handler(State)
            end
    end.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%  BEST-EFFORT BROADCAST %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

% Implementation of Best-effort Broadcast
beb_handler(State) ->
    receive      
        {beb_broadcast, {Message, Username}} -> 
        	%io:format("BEB Msg: [~p] from [~w]~n", [Message, Username]),
            % #beb_state{down = D, others = Others} = State,
            case Message of
            	{group_bc, _Payload, _GroupNodes, _GroupName} ->
            		[{beb_pid, Node} ! {pl_deliver, {broadcast_msg, Message, Username, self()}} || Node <- _GroupNodes],
            		beb_handler(State);
            	_ ->
		            [{beb_pid, Node} ! {pl_deliver, {broadcast_msg, Message, Username, self()}} || Node <- nodes()],
		            beb_handler(State)
		    end;            

        {pl_deliver, {broadcast_msg, Message, Username, _Pid}} ->
        	%io:format("BEB Msg: [~p] from [~w], delivered by [~p]~n", [Message, Username, Pid]),
        	rb_pid ! {beb_deliver, {Message, Username}},
            % #beb_state{my_up = Ups} = State,
            % [rb_pid ! {deliver, From, Msg} || Up <- sets:to_list(Ups)],
            beb_handler(State)
    end.

