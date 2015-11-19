-module (rb).
-import (beb, [bebBroadcast/2]).
-export ([init/0]).

-record (myState, {delivered = []}).

init() ->
	pass.

rbBroadcast(Message) ->
	New_State = #myState{delivered = [Message | delivered]},
	bebBroadcast({self(), Message}).

rbDeliver(Sender, Message) ->
	pass_to_upper.


