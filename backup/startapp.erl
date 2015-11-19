-module (startapp).
-export ([connect/0]).

connect() ->
	register(client_pid, spawn(startapp, client_upper, [])).
	% case whereis(client_pid) of
	% 	undefined ->
	% 		register(client_pid, spawn(startapp, client_upper, [[]]));
	% 		% register(client_pid, spawn(chat, client_lower, [ServerName, Username]));
	% 	_ -> 
	% 		already_logged_on
	% end.



%%% client process that handles message
client_upper() -> % the main function to handle requests	
	%global:whereis_name(client_pid).
	%client_upper().
	ok.

% client_upper() ->
% 	ok.