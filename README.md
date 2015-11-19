READ ME

Environment & Setup
- Open multiple Terminal windows and start Erlang under different names, representing different nodes. There is a node acting as the central point (server@localhost) for ease of connecting all the nodes in the system. Other nodes can be named, for example, node1@localhost, node2@localhost, etc
- Run either the pre-compiled file (broadcast.beam) or compile source file (broadcast.erl)
- The chat system uses both Client-Server and P2P Schemas



To use the App, following APIs are provided:
> broadcast:start_server().
	server must be started before all other nodes

> broadcast:start_client(username)
	connect to the chat system as username
	it is recommended that all the nodes should be connected and started before doing other things
> broadcast:send_message("content")
	broadcast messages to all connected users
	
> broadcast:create_group(group_name, "description")
	create a conversation group with name group_name, and detailed more with "description" (for example, "Who wants to party tonight?")

> broadcast:join_group(group_name) 
	to join a conversation group
> broadcast:leave_group(group_name) 
	to leave a conversation group
> broadcast:broadcast_group(group_name, "content to broadcast")
	to broadcast message within a group
	
