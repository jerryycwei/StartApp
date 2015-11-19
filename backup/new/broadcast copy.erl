-module (broadcast).
-export ([start_client/1, client_init/1, client_handler/2, 
			cob_handler/1, rb_handler/1, beb_handler/1,
			send_message/1, create_group/2, join_group/1, leave_group/1, broadcast_group/2,
			start_server/0, server_handler/2]).

% node as central point for ease of connection
server_node() ->
	server@localhost.

% using server as the central point to gather login and group info
% start server process
start_server() ->
	register(application_pid, spawn(broadcast, server_handler,[[],[]])),
	start_broadcast_layers(),
	io:format("Starting server~n").

% State = {OnlineUsers, ChatGroups}
server_handler(UserList, GroupList) ->
	Username = "server",
	receive
		{cob_deliver, {_Message1, _Username}} -> % msg receive from lower layer
			MsgRcpt = erlang:element(2, _Message1), % recipient list
			_Message = erlang:element(1, _Message1), % message payload
			% process message only if current node is the intended rcpt
			case lists:member(node(), MsgRcpt) of
				true ->
					case _Message of
						{user_logon, _Payload} ->
							% io:format("payload: ~p~n", [_Payload]),
							case lists:keymember(erlang:element(1, _Payload), 1, UserList) of
						        true -> % if the username is already used on other node
						        	Message1 = {username_in_use},
						        	% every message will be added with its intended recipients
						        	Message = {Message1, [erlang:element(2, _Username)]},
						        	Username = "server",
						            cob_pid ! {cob_broadcast, {Message, Username}},
									server_handler(UserList, GroupList);
						        false ->
						        	% username ok				        	
						        	%add user to the list
						        	UpdatedUserList = [_Payload | UserList],
						            Message1 = {username_ok, UpdatedUserList, GroupList},
						            Message = {Message1, [erlang:element(2, _Username)]},
						        	Username = "server",  
						        	% track current connected users  						
		     						Users = lists:flatmap(fun({Name, _}) -> [Name] end, UpdatedUserList),
						            io:format("Updated userlist:~p~n", [Users]),

						            cob_pid ! {cob_broadcast, {Message, Username}},
						            server_handler(UpdatedUserList, GroupList)			
						    end;

						 % user wants to create a new group   
						{group_create_req_server, NewGroup} ->
						 	case lists:keymember(erlang:element(1, NewGroup), 1, GroupList) of
						 		true -> % group name has been in use
						 			Message1 = {new_group_created_req, {group_name_in_use, NewGroup}},
						 			% get node name of the username as rcpt
						 			Message = {Message1, [erlang:element(2, _Username)]},
						 			% Username = "server",
						            cob_pid ! {cob_broadcast, {Message, Username}},
									server_handler(UserList, GroupList);
								false ->
									% create new group
									UpdatedGroupList = [NewGroup|GroupList],
									Message1 = {new_group_created_req, {group_name_ok, NewGroup}},
									Message = {Message1, [erlang:element(2, _Username)]},
						 			% Username = "server",
						 			% announce to user
						            cob_pid ! {cob_broadcast, {Message, Username}},				            
						 			server_handler(UserList, UpdatedGroupList)
						 	end;

						 % user wants to leave a group
						 {group_leave_req, _GroupName} ->
						 	case lists:keysearch(_GroupName, 1, GroupList) of	
						 		false -> % no group
				                    Message1 = {group_leave_res_req, {group_not_found, _GroupName}},
				                    Message = {Message1, [erlang:element(2, _Username)]},
									cob_pid ! {cob_broadcast, {Message, Username}},
									server_handler(UserList, GroupList);
								{value, {Name, Desc, MemberList}} -> % retrieve its details
									case lists:member(_Username, MemberList) of
				                		false ->% if user has not joined				                			
											Message1 = {group_leave_res_req, {non_member, _GroupName, _Username}},
											Message = {Message1, [erlang:element(2, _Username)]},
											cob_pid ! {cob_broadcast, {Message, Username}},
											server_handler(UserList, GroupList);
										true -> % if user is already a member
											% update member list of the group
						                    UpdatedMemberList = lists:delete(_Username, MemberList),
						                    io:format("Group~p: ~p -> ~p~n", [_GroupName, MemberList, UpdatedMemberList]), 

						                    UpdatedGroup = {Name, Desc, UpdatedMemberList},
						                    % update group state
						                    UpdatedGroupList = lists:keyreplace(Name, 1, GroupList, UpdatedGroup),
											Message1 = {group_leave_res_req, {user_left_success, _GroupName, _Username, UpdatedGroup}},
											Message = {Message1, [erlang:element(2, _Username)]},
											cob_pid ! {cob_broadcast, {Message, Username}},
											server_handler(UserList, UpdatedGroupList)											
									end
							end;

						% use wants to join a group
						{group_join_req, _GroupName} ->
							case lists:keysearch(_GroupName, 1, GroupList) of	
				                false -> % no group
				                    Message1 = {group_join_res_req, {group_not_found, _GroupName}},
				                    Message = {Message1, [erlang:element(2, _Username)]},
									cob_pid ! {cob_broadcast, {Message, Username}},
									server_handler(UserList, GroupList);
				                {value, {Name, Desc, MemberList}} -> % retrieve its details
				                	% updated all group details before updating the global state
				                	case lists:member(_Username, MemberList) of
				                		false ->% if user has not joined		         
				                			% update member list of the group   				                			
						                    UpdatedMemberList = [_Username | MemberList],
						                    io:format("Group~p: ~p -> ~p~n", [_GroupName, MemberList, UpdatedMemberList]), 
						                    UpdatedGroup = {Name, Desc, UpdatedMemberList},
						                    % update group state
						                    UpdatedGroupList = lists:keyreplace(Name, 1, GroupList, UpdatedGroup),
											Message1 = {group_join_res_req, {user_joined_success, _Username, _GroupName, UpdatedGroup}},
											Message = {Message1, [erlang:element(2, _Username)]},
											cob_pid ! {cob_broadcast, {Message, Username}},
											server_handler(UserList, UpdatedGroupList);
										true -> % if user is already a member
											% io:format("Hello world~n"),
											Message1 = {group_join_res_req, {already_a_member, _GroupName, _Username}},
											Message = {Message1, [erlang:element(2, _Username)]},
											cob_pid ! {cob_broadcast, {Message, Username}},
											server_handler(UserList, GroupList)
									end					

				            end;
				         % other kind of message
						_ ->
						    server_handler(UserList, GroupList)
					end;
				% _ ->
				% 	server_handler(UserList, GroupList)
				false ->
					server_handler(UserList, GroupList)
			end

	end,
	server_handler(UserList, GroupList).


start_client(Username) ->
	% connect to the central node
	net_kernel:connect_node(server_node()),
	% 
    case whereis(application_pid) of 
        undefined ->
        	% register the application layer process
            register(application_pid, spawn(broadcast, client_init,[Username])),
            start_broadcast_layers(),
            % validate username againts server
           	Message1 = {user_logon, {Username, node()}},
           	Message = {Message1, [server_node()]},
			cob_pid ! {cob_broadcast, {Message, {Username, node()}}};
        _ -> 
        	io:format("You have already logged on this node!~n")
    end.


% run client while waiting for username validation	
client_init(Username) ->
	receive
		{cob_deliver, {_Msg, _Username}} ->
			MsgRcpt = erlang:element(2, _Msg),
			_Message = erlang:element(1, _Msg),
			case lists:member(node(), MsgRcpt) of
				true -> % process only if being intended rcpt
					% io:format("Problem: ~p, [~p]~n", [_Message, _Username]),
					case _Message of
						{username_in_use} ->
							% if the username is in use, deregister all processes
							io:format("Sorry, this username is in use!~n"),
							unregister(application_pid),
							unregister(rb_pid),
							unregister(beb_pid),
							unregister(cob_pid),
							exit(normal);				
						{username_ok, UserList, GroupList} -> %otherwise say hello
							% and start user app
							io:format("Hello ~p~n", [erlang:element(1, Username)]),
							io:format("Available chat group(s): ~p~n", [GroupList]),
							% register with current userlist and grouplist
							State = {GroupList, UserList},
							% let other knows that you've logged in!
							application_pid ! {new_user_connected_req},
							client_handler(State, Username);
						_ ->
							client_init({Username, node()})
					end;
				false -> % drop msg
					client_init({Username, node()})
			end

	end,
	client_init({Username, node()}).

% cob_handler ! {cob_broadcast, {Username, Message}},

% reigster the broadcasting service layer processes
start_broadcast_layers() ->
	register(cob_pid, spawn(broadcast, cob_handler,[{[],[]}])),
	register(rb_pid, spawn(broadcast, rb_handler,[{[]}])),
	register(beb_pid, spawn(broadcast, beb_handler,[[]])).
	
% broad message to everybody connected to the system
send_message(Message) ->
	application_pid ! {msg_send_req, Message}.

% create a new group
create_group(GroupName, Description) ->
	application_pid ! {group_create_req, GroupName, Description}.

% join a grop
join_group(GroupName) ->
	application_pid ! {group_join_req, GroupName}.

% leave a group
leave_group(GroupName) ->
	application_pid ! {group_leave_req, GroupName}.

% broadcast message to a group
broadcast_group(GroupName, Message) ->
	application_pid ! {group_broadcast_req, GroupName, Message}.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% APPLICATION LAYER %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

% client_handler(State) ->
%	pass.
% State = {GroupList}; GroupList = [Group1, Group2, ..]
% Group = {Name, Desc, [{Member1, node1}, {Member2, Node2}..]}
client_handler(State, Username) ->
	GroupList = erlang:element(1, State),
	UserList = erlang:element(2, State),
	receive
		{cob_deliver, {_Msg, _Username}} ->
			MsgRcpt = erlang:element(2, _Msg), % intented rcpt
			_Message = erlang:element(1, _Msg),
			case lists:member(node(), MsgRcpt) of
				true -> % process only if being intended rcpt
					case _Message of
						% for regular message
						{regular_msg, Data} ->
							application_pid ! {msg_send_ind, Data, _Username},
							client_handler(State, Username);
						% response from server for connecting
						{new_user_connected_req, _Payload} ->				
							application_pid !  {new_user_connected_ind, _Payload},
							client_handler(State, Username);

						% response from server for creating new group
						{new_group_created_req, _Payload} ->
							application_pid !  {new_group_created_ind, _Payload},
							client_handler(State, Username);
						% group sync 
						{group_sync_req, UpdatedGroup} ->
							application_pid !  {group_sync_ind, UpdatedGroup},
							client_handler(State, Username);
						% notifcation of user joining/leaving a group
						{group_notif_req, _GroupName, _Username, _Notif} ->
							application_pid !  {group_notif_ind, _GroupName, _Username, _Notif},
							client_handler(State, Username);
						
						% response from server for joining a group
						{group_join_res_req, _Payload} ->
							application_pid !  {group_join_res_ind, _Payload},
							client_handler(State, Username);

						% response from server for leaving a group
						{group_leave_res_req, _Payload} ->
							application_pid !  {group_leave_res_ind, _Payload},
							client_handler(State, Username);

						% normal broadcast message
						{group_broadcast_req, _BCMsg, _GroupName} ->
							application_pid !  {group_broadcast_ind, _BCMsg, _GroupName, _Username},
							client_handler(State, Username);
						_ -> % others
							% io:format("[~w]: ~p~n", [_Username, _Message]),
							client_handler(State, Username)
					end;
				false -> % if not the rcpt ignore the msg
					client_handler(State, Username)
			end;
			

		% broadcast new user logon to everybody
		{new_user_connected_req} ->
			Message1 = {new_user_connected_req, Username},
			Message = {Message1, nodes()},
			cob_pid ! {cob_broadcast, {Message, Username}},			
			client_handler(State, Username);

		{new_user_connected_ind, NewUser} ->			
			UpdatedUserList = [NewUser|UserList],
			UpdatedState = erlang:setelement(2, State, UpdatedUserList),
			io:format("~p has just joined the chat!~n", [erlang:element(1, NewUser)]),
			client_handler(UpdatedState, Username);			
			

		{msg_send_req, _Message} ->
			%io:format("Message from ~w: ~p~n", [Username, _Message]),
			Message1 = {regular_msg, _Message},
			Message = {Message1, nodes()},
			cob_pid ! {cob_broadcast, {Message, Username}},
			client_handler(State, Username);
		%
		{msg_send_ind, _Message, _Username} ->
			io:format("[~p]: ~p~n", [erlang:element(1,_Username), _Message]),			
			client_handler(State, Username);

		% request to create group
		{group_create_req, GroupName, Description} ->
			%GroupList = erlang:element(1, State),
			Group = {GroupName, Description, [Username]},			
			% Message = {group_info, UpdatedGroupList},
			Message1 = {group_create_req_server, Group},
			% send down
			Message = {Message1, [server_node()]},
			cob_pid ! {cob_broadcast, {Message, Username}},
			client_handler(State, Username);
		% notication of successful creation of group

		% send request to server for new group creation
		{new_group_created_ind, _Payload} ->
			case _Payload of
				{group_name_in_use, _NewGroup} ->
					io:format("Sorry, this group name has been in use!~n"),
					client_handler(State, Username);
				{group_name_ok, NewGroup} ->
					% if (erlang)
					io:format("New group '~p' created successfully!~n", [erlang:element(1, NewGroup)]),
					UpdatedGroupList = [NewGroup | GroupList],
					UpdatedState = erlang:setelement(1, State, UpdatedGroupList),
					
					% sync group list with all others					
					SyncMsg1 = {group_sync_req, NewGroup},
					SyncMsg  = {SyncMsg1, nodes()},
					cob_pid ! {cob_broadcast, {SyncMsg, Username}},
					
					client_handler(UpdatedState, Username)
			end;

		{group_sync_ind, UpdatedGroup} ->
			GroupName = erlang:element(1, UpdatedGroup),
			MemberUsernames = lists:flatmap(fun({Usn, _}) -> [Usn] end, erlang:element(3, UpdatedGroup)),	
			% add new group created to current list
			case lists:member(UpdatedGroup, GroupList) of
				true -> % if group already exists					
					UpdatedGroupList = lists:keyreplace(GroupName, 1, GroupList, UpdatedGroup),
					io:format("Group members now are: ~p~n", [MemberUsernames]);
				false -> % new group
					UpdatedGroupList = [UpdatedGroup | GroupList]
					% io:format("~p just created a new group named '~p'", [lists:nth(1, MemberUsernames), GroupName])
					% then update state					
			end,
			UpdatedState = erlang:setelement(1, State, UpdatedGroupList),
			client_handler(UpdatedState, Username);

		% send a req to server node to join a group
		{group_join_req, _GroupName} ->
			Message1 = {group_join_req, _GroupName},			
			Message = {Message1, [server_node()]},
			cob_pid ! {cob_broadcast, {Message, Username}},
			client_handler(State, Username);

		% node acts upon receiving server's response for group join request
		{group_join_res_ind, _Payload} ->
			case _Payload of 
				{already_a_member, _GroupName, _Username} ->
					io:format("~p already joined the group '~p'~n", [erlang:element(1, _Username), _GroupName]),
					client_handler(State, Username);
				{group_not_found, _GroupName} ->
					io:format("Group '~p' cannot be found~n", [_GroupName]),
					client_handler(State, Username);
				{user_joined_success, _Username, _GroupName, _UpdatedGroup} ->					
					MemberUsernames = lists:flatmap(fun({Usn, _}) -> [Usn] end, erlang:element(3, _UpdatedGroup)),					
					% update current group list
					UpdatedGroupList = lists:keyreplace(_GroupName, 1, GroupList, _UpdatedGroup),
					UpdatedState = erlang:setelement(1, State, UpdatedGroupList),
					
					% sync to other users
					SyncMsg1 = {group_sync_req, _UpdatedGroup},
					SyncMsg  = {SyncMsg1, nodes()},
					cob_pid ! {cob_broadcast, {SyncMsg, Username}},

					% broadcast to all other nodes
					% MemberList = erlang:element(3, _UpdatedGroup), % all members
					MemberNodes = lists:flatmap(fun({_, Node}) -> [Node] end, erlang:element(3, _UpdatedGroup)),					
					% except current node
					OtherMemberNodes = lists:delete(node(), MemberNodes),
					JoinMsg1  = {group_notif_req, _GroupName, _Username, {join}},
					JoinMsg = {JoinMsg1, OtherMemberNodes},
					cob_pid ! {cob_broadcast, {JoinMsg, Username}},

					% visible to group only
					io:format("Group members now are: ~p~n", [MemberUsernames]),
					% io:format("~p has joined conversation group '~p'~n", [erlang:element(1, _Username), _GroupName]),
					client_handler(UpdatedState, Username)
			end;

		{group_leave_req, _GroupName} ->
			Message1 = {group_leave_req, _GroupName},			
			Message = {Message1, [server_node()]},
			cob_pid ! {cob_broadcast, {Message, Username}},
			client_handler(State, Username);

		{group_leave_res_ind, _Payload} ->
			case _Payload of 
				{non_member, _GroupName, _Username} -> % not joined yet
					io:format("You are not member of the group '~p'~n", [_GroupName]),
					client_handler(State, Username);
				{group_not_found, _GroupName} -> % no such group
					io:format("Group '~p' cannot be found~n", [_GroupName]),
					client_handler(State, Username);
				{user_left_success, _GroupName, _Username, _UpdatedGroup} ->				
					MemberUsernames = lists:flatmap(fun({Usn, _}) -> [Usn] end, erlang:element(3, _UpdatedGroup)),					
					% update current group list
					UpdatedGroupList = lists:keyreplace(_GroupName, 1, GroupList, _UpdatedGroup),
					UpdatedState = erlang:setelement(1, State, UpdatedGroupList),
					
					% sync to other users
					SyncMsg1 = {group_sync_req, _UpdatedGroup},
					SyncMsg  = {SyncMsg1, nodes()},
					cob_pid ! {cob_broadcast, {SyncMsg, Username}},

					% broadcast to all other nodes
					% MemberList = erlang:element(3, _UpdatedGroup), % all members
					MemberNodes = lists:flatmap(fun({_, Node}) -> [Node] end, erlang:element(3, _UpdatedGroup)),					
					% except current node
					OtherMemberNodes = lists:delete(node(), MemberNodes),
					JoinMsg1  = {group_notif_req, _GroupName, _Username, {leave}},
					JoinMsg = {JoinMsg1, OtherMemberNodes},
					cob_pid ! {cob_broadcast, {JoinMsg, Username}},

					% visible to group only
					io:format("Group members now are: ~p~n", [MemberUsernames]),
					% io:format("~p has left conversation group '~p'~n", [erlang:element(1, _Username), _GroupName]),
					client_handler(UpdatedState, Username)
			end;


		{group_notif_ind, _GroupName, _Username, _Notif} ->

			case _Notif of
				{join} ->
					io:format("~w has joined ~p~n", [erlang:element(1, _Username), _GroupName]),
					% io:format("Current group members: ~p~n", [GroupList]),
					client_handler(State, Username);
				{leave} ->
					io:format("~w has left ~p~n", [erlang:element(1, _Username), _GroupName]),
					% io:format("Current group members: ~p~n", [GroupList]),
					client_handler(State, Username)
			end;

		{group_broadcast_req, _GroupName, BCMessage} ->
			case lists:keysearch(_GroupName, 1, GroupList) of
                false ->
                    io:format("Group not found!"),
                    client_handler(State, Username);
                {value, {_Name, _Desc, MemberList}} ->
         			case lists:member(Username, MemberList) of
                		true -> %if the current user is in group
                			% get the node involved
		                	GroupNode = lists:flatmap(fun({_, Node}) -> [Node] end, MemberList),
		            		Message1 = {group_broadcast_req, BCMessage, _Name},
		            		Message = {Message1, GroupNode},
							cob_pid ! {cob_broadcast, {Message, Username}},
							client_handler(State, Username);
						false ->
							io:format("Sorry, you can't post in group you haven't joined!~n"),
							client_handler(State, Username)
					end

            end;

        {group_broadcast_ind, _Message, _GroupName, _Username} ->
        	io:format("[~p] via [~p]: ~p~n", [erlang:element(1,_Username), _GroupName, _Message]),
        	client_handler(State, Username);
        % other
        _ ->
        	io:format("Unknown request!~n"),
        	client_handler(State, Username)

	end.

% The underlying Broadcast service layer are transparent to the application message
% Message are encapsulated with suitable atom keyword when necessary 
% for special message
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%  BROADCAST ALGORITHM LAYER %%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

%%%%%%%%%%%%%%%%%%%%%%  CAUSAL RELIABLE ORDER BROADCAST %%%%%%%%%%%%%%%%%%%%%%%%%%

% State = {Delivered, History} = {{[{Message}], [{Message, Username}]}
cob_handler(State) ->	
	Delivered = erlang:element(1, State),
	History = erlang:element(2, State),
	receive
		{cob_broadcast, {_Message, Username}} ->
			% add time and node name as id for message
			Message = {_Message, erlang:now(), node()},
			% pass down to RB layer
			rb_pid ! {rb_broadcast, {History, Message, Username}},
			% append new msg to history, from right to left
			% for the sake of retrieving
			NewHistory = lists:append(History, [{Message, Username}]),
			cob_handler({Delivered, NewHistory});

		{rb_deliver, {_History, _Message, _Username}} ->
			% if the message is not yet delivered
			case lists:keymember(_Message, 1, Delivered) of
				false ->
					% run through the history of message
					lists:foreach(	
						fun(X) -> % list of {Message, Username}
							%if any msg is not delivered yet
							HistoryMsg = erlang:element(1, X),
							case lists:keymember(HistoryMsg, 1, Delivered) of
								false -> % if not
									% strip out time and node name
									Message = erlang:element(1, HistoryMsg),
									% deliver it to upper layer (user)
									application_pid ! {cob_deliver, Message},
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
					% strip out the time and node info
					Msg = erlang:element(1, _Message),
					application_pid ! {cob_deliver, {Msg, _Username}},
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
            beb_pid ! {beb_broadcast, {Message, Username}},
            rb_handler(State);


        {beb_deliver, {Message, Username}} ->
            DeliveredMsg = erlang:element(1, State),
           	case lists:keymember(Message, 1, DeliveredMsg) of
           		false ->         
           			% update the Delivered list of message 	
                    UpdatedDeliveredMsg = [{Message} | DeliveredMsg],
                    History = [],
                    cob_pid ! {rb_deliver, {History, Message, Username}},
                    beb_pid ! {beb_broadcast, {Message, Username}},
                    % update the state
                    rb_handler({UpdatedDeliveredMsg});
                true -> 
                	rb_handler(State)
            end
    end.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%  BEST-EFFORT BROADCAST %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

% Implementation of Best-effort Broadcast
beb_handler(State) ->
	% io:format("i amn here lol"),
    receive      
        {beb_broadcast, {Message, Username}} -> % lowest layer of broadcast server, erlang's perfect-link channel is used after that
            [{beb_pid, Node} ! {pl_deliver, {broadcast_msg, Message, Username, self()}} || Node <- nodes()],
		    beb_handler(State);            

        {pl_deliver, {broadcast_msg, Message, Username, _Pid}} ->
        	% io:format("i amn here lol"),
        	rb_pid ! {beb_deliver, {Message, Username}},
            beb_handler(State)
    end.

