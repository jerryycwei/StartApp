-module (chat).
-export ([	disconnect/1, server_run/1, start_server/0,connect/1, 
			start_client/2, message_send/2, message_send_all/2, broadcast/2, client_handler/3,
			message_broadcast/1,
			group_list/0, group_create/1, group_leave/1, group_join/1]).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% APPLICATION LAYER %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

connect(Username) ->
	% spawn a client process to handle request send to a client once connected
	% global:register_name(client_pid, spawn(chat, start_client, [Username, server_node()])).
	case whereis(client_pid) of 
        undefined ->
            register(client_pid, spawn(chat, start_client, [Username, server_node()]));
        _ -> already_logged_on
    end.

%disconnect last connected user
disconnect(Username) ->
	% client_pid ! {disconnect, self(), server_node()}.	
	{chat_server, server_node()} ! {whereis(Username), client_disconnected},
	unregister(Username).


message_broadcast(Msg) ->
	client_pid ! {msg_broadcast, Msg}.


message_send(Username, Msg) ->
	client_pid ! {msg_sent, Username, Msg}.

 
message_send_all(User_list, Msg) ->
	pass.


% UTILITY FUNCTIONS
% broadcast a message to a list of user
broadcast(Msg, User_list) ->
	[Pid ! {broadcast_msg_receive, Msg} || {Pid, Username} <- User_list].

broadcast(Msg, User_list, Sender) ->
	[Pid ! {broadcast_msg_receive, Msg, Sender} || {Pid, Username} <- User_list].

% broadcast(Username, Pid) ->
% 	%self() ! {broadcast, Username, node(), global:whereis_name(client_pid)}.
% 	self() ! {broadcast, Username, node(), whereis(client_pid)}.

%broadcast(User_list)
	% if [User|Other_users] -> it's a list, send recursively to all
		% broadcast(User)
		% broadcast(Other_users)
	% if User -> it's just a user, send 1

start_client(Username, ServerNode) ->
	io:format("Hello ~p~n", [Username]),
	{chat_server, ServerNode} ! {self(), connect, Username},
	%broadcast(Username),
	client_handler(Username, [], []).



%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% APPLICATION LAYER %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

% a loop process that handles requests from client
% Group_list = [{GroupName, StarterPID GroupUser_list}]
% Maybe there could be another client_handler which has only 1 param (withtout Group_list)
client_handler(Username, User_list, Group_list) ->
	receive		
		{broadcast, _Username, _Node, _Pid} -> % handles the broadcats message
			io:format("broadcast arrived: ~n"),
			% lists:foreach(
			% 	fun(X)->
			% 		io:format("~w ",[X]) 
			% 	end, 
			% 	User_list
			% ).
			[{Pid, Node} ! {bc_hello, _Pid, _Node, _Username} || {Pid, Node, Username} <- User_list],				
			client_handler(Username, User_list, Group_list);

		% broadcast receive from server for updated user list
		{broadcast_msg_receive, Updated_user_list} ->
			% should remove self PID/User name from the list
			lists:keydelete(Username, 2, Updated_user_list),
			io:format("Other online users (updated): ~p~n", [Updated_user_list]),
			client_handler(Username, Updated_user_list, Group_list);

		% broadcast received from other users
		{broadcast_msg_receive, Message, Sender} ->
			io:format("Broadcast message from ~w: ~p~n", [Sender, Message]),
			client_handler(Username, User_list, Group_list);

		{bc_hello, Pid, Node, Username} -> % receives a hello from other client
			[{Pid, Node, Username} | User_list],
			client_handler(Username, User_list, Group_list);

		{msg_sent, RecipientUsn, Msg} ->
			% should be handled by lower layer
			% User_list format: [{Username, Pid, Node}]
			% search for the username in the tuple list
			%io:format("everything is alright!~n"),

			case lists:keysearch(RecipientUsn, 2, User_list) of
					false -> % nothing found
						recipient_username_not_found;
					{value, {RcptPid, RcptUsn}} -> % tuple returned
						%io:format("Send message ~w to user ~w with pid ~w~n", [Msg, RcptUsn, RcptPid]),
						RcptPid ! {msg_received, RcptUsn, Msg, Username, self()}
			end,
			client_handler(Username, User_list, Group_list);

		{msg_broadcast, Msg} ->
			io:format("broadcast requested~n"),
			broadcast(Msg, User_list, Username), % WHY ONLY 1 TIME?
			client_handler(Username, User_list, Group_list);



		{msg_received, _RecipientUsn, Msg, SenderUsn, SenderPid} ->
			% when receiving a message sent by another
			io:format("~w: ~p~n", [SenderUsn, Msg]),
			%log system works here to record into Riak later
			client_handler(Username, User_list, Group_list);

		group_list_req ->
			io:format("List all avaiable groups on server!"),
			client_handler(Username, User_list, Group_list)
	end.




%%%% ROUTER LAYER %%%%%%%%%
%%% Involve logical dispatching
client_router_layer() ->
	receive
		% Message = {Pid, Usersname}
		{broadcast, Message} -> %send message to all nodes connected
			sent,
			client_link_layer();
		{unicast, Node, Message} -> % send message to 1 specific node
			sent,
			client_link_layer()
	end.

%%% LINK LAYER OF CLIENT
%%% 
client_link_layer() ->
	receive
		% Message = {Pid, Message}, Message = {Username, Node, etc}
		{broadcast, Message} -> %send message to all nodes connected
			sent,
			client_link_layer();
		{unicast, Node, Message} -> % send message to 1 specific node
			sent,
			client_link_layer()
	end.






%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%% SERVER SIDE %%%%%%%%%%%%%%%%%%%%%%%%%%%%

server_node() ->
	chat_server@localhost.

start_server() -> % start chat server
	register(chat_server, spawn(chat, server_run, [[]])).

%%% Server should maintain the list of online user
server_run(User_list) ->
	receive
		% receive a connect request from client
		{From, connect, Name} ->
            Updated_user_list = server_logon(From, Name, User_list),
            io:format("User ~w signed in!~n", [Name]),
            io:format("Current online user(s): ~p~n", [Updated_user_list]),
            % broadcast an updated online user list 
            broadcast(Updated_user_list, Updated_user_list),
            server_run(Updated_user_list);

         % receives a disconnect request from client
        {From, client_disconnected} ->
            Updated_user_list = server_logoff(From, User_list),
            io:format("User ~w signed out!~n", [From]),
            io:format("Current online user(s): ~p~n", [Updated_user_list]),
            broadcast(Updated_user_list, Updated_user_list),
            server_run(Updated_user_list)
	end.

server_logon(SenderPid, Username, User_list) ->
    %% check if logged on anywhere else
    case lists:keymember(Username, 2, User_list) of
        true -> % if the username is already used on other node
            SenderPid ! {messenger, stop, user_exists_at_other_node},  %reject logon
            User_list;
        false ->
            SenderPid! {messenger, logged_on},
            [{SenderPid, Username} | User_list]     %add user to the list
    end.

%%% Server deletes a user from the user list
server_logoff(From, User_List) ->
    lists:keydelete(From, 1, User_List).


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% CHAT ROOM %%%%%%%%%%%%%%%%%%%%%%%%%%
%%% Group infor should also be stored on server/private
group_create(GroupName) ->
	% {GroupName, User_list}
	% % Group_list = [{GroupName, StarterPID GroupUser_list}]
	pass.

group_list() ->
	client_pid ! group_list_req.

group_join(GroupName) ->
	pass.

group_leave(GroupName) ->
	pass.

group_broadcast(GroupName, Message) ->
	%broadcast msg to all ppl in 1 group
	% user can only broadcast to groups that he's joined
	pass.
	



