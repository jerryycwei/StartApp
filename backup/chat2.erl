

-export ([send_msg/2,start_server/0, server_run/1, client_run/2, disconnect/0, connect/2]).
-module (chat).


%%% CLIENT SIDE %%% 

% start() ->
% 	register(pid, spawn(basic3, pong, [])).

% broadcast(join, UserList, {Username}) ->
% 	new_user_just_joined;

% broadcast(Message, Users, {}) -> % the actual function that broadcasts messages to all users
% 	lists:foreach(
% 		fun({_, Pid}) -> 
% 			Pid ! Message 
% 		end,
% 		Users
% 	).

%% user login to chat server
%% a new process is created for each node logged in
connect(Username, ServerName) ->
	case whereis(client_pid) of
		undefined ->
			register(client_pid, spawn(chat, client_run, [ServerName, Username]));
			% register(client_pid, spawn(chat, client_lower, [ServerName, Username]));
		_ -> 
			already_logged_on
	end.

disconnect() ->
	client_pid ! disconnect.

%%% client process that handles message
client_run(_ServerName, _Username) -> % the main function to handle requests
	% receive
	% 	{connect, ServerName, Username}
	% 		{}
	% end,
	% client_run(ServerName, Username)
	{chat_server, _ServerName} ! {self(), connect, _Username},
	await_result(),
	client_run(_ServerName).

client_run(_ServerName) ->
	receive
		disconnect -> % when client sends a disconnect signal
			{chat_server, _ServerName} ! {self(), disconnect},
			exit(normal);
		{message_to, _Username, _Message} -> % a command to send message
			% TODO: pass it down to lower layer
			% client_lower ! {unicast, _Username, _Message}
			% send a query username -> pid to server
			{chat_server, _ServerName} ! {query_username, _Username, self()};
		{recv_pid, Message, SenderPid} ->
			recv_pid ! {msg_sent, Message, SenderPid},

		{msg_sent}


	end.

send_msg(_Username, _Message) ->
	% TODO: check if client is logged on
	case whereis(client_pid) of
		 % if there's no client_pid registerd on this node
		 % ie. not logged in yet
		undefined ->
			io:format("You need to log in first!~n"),
			not_logged_in;
		_ -> % else
			% let the client process handle the message sending 
			client_pid ! {message_to, _Username, _Message},
			message_sent

	end.

%%% wait for a response from the server
await_result() ->
    receive
        {messenger, stop, Why} -> % Stop the client 
            io:format("~p~n", [Why]),
            exit(normal);
        {messenger, What} ->  % Normal response
            io:format("~p~n", [What])
    end.

%%% LOWER LAYER

client_lower() -> % the lower layer of client that handles message transfer
	receive
		{unicast, Message, Recipient} ->
			unicast(Recipient, Message);
		{broadcast, Message, Recipient} ->
			broadcast(Message)
	end.

unicast(Pid, Message) -> %% handle the pass
	Pid ! Message,
	message_sent.
	

broadcast(Message) ->
	%broadcast message done here
	message_broadcasted.



%%% SERVER SIDE %%%
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