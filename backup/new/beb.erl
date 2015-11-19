-module (beb).
%-import (rb, [function/arity]).
-export ([bebBroadcast/2, bebDeliver/2]).


%-record (state, {upper_pids = [], down = Pid}).

all_processes() ->
	erlang:registered().

sendTo(To, Message) ->
	To ! {Message, self()}.

bebBroadcast(Message, Pids) ->
	[sendTo(Pid, Message) || Pid <- Pids].

% should pass the message to upper layer

bebDeliver(Pid, {Data,  Sender, Message, Delivered}) ->

	case lists:keymember(Message, 1, Delivered) of
		false ->
			New_State = Delivered = lists:append([Message], Delivered),
		_ ->
			pass
	end,
	rbDeliver(Sender, Message),
	bebBroadcast({Data, Sender, Message}).
	 
