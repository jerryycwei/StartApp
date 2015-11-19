-module (chat).
-export ([connect/1, start_client/1, send_message/2, send_message_all/2, broadcast/3]).

connect(Username) ->
	% spawn a client process to handle request send to a client once connected
	global:register_name(client_pid, spawn(chat, start_client, [Username])).

broadcast(Username, Pid, Node) ->
	self() ! {broadcast, Username, node(), global:whereis_name(client_pid)}.

start_client(Username) ->
	io:format("Hello ~p~n", [Username]),
	%broadcast(Username),
	client_handler([]).

% a loop process that handles requests from client
client_handler(Userlist) ->
	receive		
		{broadcast, _Username, _Node, _Pid} -> % handles the broadcats message
			io:format("broadcast arrived: ~n"),
			% lists:foreach(
			% 	fun(X)->
			% 		io:format("~w ",[X]) 
			% 	end, 
			% 	Userlist
			% ).
			[{Pid, Node} ! {bc_hello, _Pid, _Node, _Username} || {Pid, Node, Username} <- Userlist],				
			client_handler(Userlist);
		{bc_hello, Pid, Node, Username} -> % receives a hello from other client
			[{Pid, Node, Username} | Userlist],
			client_handler(Userlist);
		{msg_sent, RecipientUsn, Msg, SenderUsn} ->
			% should be handled by lower layer
			% userlist format: [{Username, Pid, Node}]
			% search for the username in the tuple list
			case lists:keysearch(RecipientUsn, 1, Userlist) of
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

		disconnect ->
			client_disconnected
	end.

% send_message(Username, Msg) -> % send a message to another user
% 	client_pid ! {msg_sent, Username, Msg}.

send_message(Node, Msg) ->
	{Node, client_pid} ! {regular_msg, Msg}.

 
send_message_all(Userlist, Msg) ->
	pass.

%%% LINK LAYER OF CLIENT
%%% Should have 
client_link_layer() ->
	receive
		% Message = {Pid, Usersname}
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
            New_User_List = server_logon(From, Name, UserList),
            server_run(New_User_List);
        {From, disconnect} ->
            New_User_List = server_logoff(From, UserList),
            server_run(New_User_List);
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