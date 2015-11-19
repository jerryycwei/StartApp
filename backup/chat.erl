-module (chat).
-export ([disconnect/0, disconnect/1, server_run/1, start_server/0,connect/1, start_client/2, send_message/2, send_message_all/2, broadcast/3]).

connect(Username) ->
	% spawn a client process to handle request send to a client once connected
	% global:register_name(client_pid, spawn(chat, start_client, [Username, server_node()])).
	register(client_pid, spawn(chat, start_client, [Username, server_node()])).

%disconnect last connected user
disconnect() ->
	% client_pid ! {disconnect, self(), server_node()}.	
	{chat_server, server_node()} ! {whereis(client_pid), client_disconnected},
	unregister(client_pid).

% disconnect user with username
disconnect(_Username) ->
	pass.

broadcast(Username, Pid) ->
	%self() ! {broadcast, Username, node(), global:whereis_name(client_pid)}.
	self() ! {broadcast, Username, node(), whereis(client_pid)}.

start_client(Username, ServerNode) ->
	io:format("Hello ~p~n", [Username]),
	{chat_server, ServerNode} ! {self(), connect, Username},
	%broadcast(Username),
	client_handler([]).

% a loop process that handles requests from client
% GroupList = [{GroupName, GroupUserList}]
client_handler(UserList, GroupList) ->
	receive		
		{broadcast, _Username, _Node, _Pid} -> % handles the broadcats message
			io:format("broadcast arrived: ~n"),
			% lists:foreach(
			% 	fun(X)->
			% 		io:format("~w ",[X]) 
			% 	end, 
			% 	UserList
			% ).
			[{Pid, Node} ! {bc_hello, _Pid, _Node, _Username} || {Pid, Node, Username} <- UserList],				
			client_handler(UserList);
		{bc_hello, Pid, Node, Username} -> % receives a hello from other client
			[{Pid, Node, Username} | UserList],
			client_handler(UserList);
		{msg_sent, RecipientUsn, Msg, SenderUsn} ->
			% should be handled by lower layer
			% UserList format: [{Username, Pid, Node}]
			% search for the username in the tuple list
			case lists:keysearch(RecipientUsn, 1, UserList) of
					false -> % nothing found
						recipient_username_not_found;
					{value, {Username, Pid}} -> % tuple returned
						Pid ! {Username, msg_received, Msg, SenderUsn, self()}
			end;
		{RecipientUsn, msg_received, Msg, SenderUsn, SenderPid} ->
			% when receiving a message sent by another
			io:format("~p: ~p", [SenderUsn, Msg]);
			%log system works here to record into Riak later

		{regular_msg, Msg} ->
			io:format("Receive msg: ~w~n", [Msg]);

		{online_user_updated, UpdatedUserList} ->
			% maybe more work on this to remove self()
			UserList = UpdatedUserList,
			client_handler(UpdatedUserList)

		% {disconnect, Pid, ServerNode} ->
		% 	{chat_server, ServerNode} ! {Pid, client_disconnected}
	end.

% send_message(Username, Msg) -> % send a message to another user
% 	client_pid ! {msg_sent, Username, Msg}.

send_message(Node, Msg) ->
	{Node, client_pid} ! {regular_msg, Msg}.

 
send_message_all(UserList, Msg) ->
	pass.

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
server_run(UserList) ->
	receive
		{From, connect, Name} ->
            UpdatedUserList = server_logon(From, Name, UserList),
            io:format("User ~w signed in!~n", [Name]),
            io:format("Current online user(s): ~p~n", [UpdatedUserList]),
            server_run(UpdatedUserList);
        {From, client_disconnected} ->
            UpdatedUserList = server_logoff(From, UserList),
            io:format("User ~w signed out!~n", [From]),
            io:format("Current online user: ~p~n", [UpdatedUserList]),
            server_run(UpdatedUserList);
        % {From, message_to, To, Message} ->
        %     server_transfer(From, To, Message, UserList),
        %     io:format("list is now: ~p~n", [UserList]),
        %     server_run(User_List)
        {query_username, Username, SenderPid, Message} ->
        	case lists:keysearch(Username, 2, UserList) of
        		false ->
        			pass;
        		{value, {RecvPid, Username}} -> % found username
        			SenderPid ! {recv_pid, Message, SenderPid}
        	end
	end.

server_logon(SenderPid, Username, UserList) ->
    %% check if logged on anywhere else
    case lists:keymember(Username, 2, UserList) of
        true -> % if the username is already used on other node
            SenderPid ! {messenger, stop, user_exists_at_other_node},  %reject logon
            UserList;
        false ->
            SenderPid! {messenger, logged_on},
            [{SenderPid, Username} | UserList]        %add user to the list
    end.

%%% Server deletes a user from the user list
server_logoff(From, User_List) ->
    lists:keydelete(From, 1, User_List).


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% CHAT ROOM %%%%%%%%%%%%%%%%%%%%%%%%%%
create_group(GroupName) ->
	% {GroupName, UserList}
	pass.

list_group(ServerNode) ->
	pass.




