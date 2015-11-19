%% ALL THE MESSAGE DISPLAY SHOULD BE DONE ON APPLICATION LAYER

-module (client).
-export ([  disconnect/0,connect/1, 
            start_client/2,
            message_broadcast/1, message_send/2, 
            group_list/0, group_create/2, group_leave/1, group_join/1, group_broadcast/2,
            app_handler/0, logic_handler/3, transmission_handler/2
            ]).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% APPLICATION LAYER %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

server_node() ->
    chat_server@localhost.


connect(Username) -> 
    case whereis(client_pid) of 
        undefined ->
            register(client_pid, spawn(client, transmission_handler, [Username, server_node()])),            
            register(logic_layer, spawn(client, logic_handler, [Username, [], []])),
            register(app_layer, spawn(client, start_client, [Username, server_node()]));
        _ -> 
            already_logged_on
    end.

disconnect() ->
    logic_layer ! client_disconnect.

message_broadcast(Msg) ->
    logic_layer ! {msg_broadcast, Msg}.

message_send(Username, Msg) ->
    logic_layer ! {msg_send, Username, Msg}.

group_create(Name, Description) ->
    logic_layer ! {group_create_req, Name, Description}.
    
group_list() ->
    logic_layer ! group_list_req.

group_list_active() ->
    logic_layer ! group_list_active_req.

group_join(GroupName) ->
    logic_layer ! {group_join_req, GroupName}.

group_leave(GroupName) ->
    logic_layer ! {group_leave_req, GroupName}.

group_broadcast(GroupName, Message) ->    
    logic_layer ! {group_broadcast_req, GroupName, Message}.

% The main loop for application layer process
app_handler() ->
    receive
        {bc_receive, Message, Sender} ->
            %io:format("Broadcast message from ~w: ~p~n", [Sender, Message]),
            display_something

    end,
    app_handler().


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% LOGIC LAYER %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%


start_client(Username, ServerNode) ->
    io:format("Hello ~p~n", [Username]),
     client_pid ! {message_out, {chat_server, ServerNode}, {self(), connect, Username}},
    logic_handler(Username, [], []).


logic_handler(Username, UserList, GroupList) ->
    receive
        % broadcast receive from server for updated user list
        {bc_receive, BroadcastMsg} ->
            % should remove self PID/User name from the list
            case BroadcastMsg of
                {updated_user_list, UpdatedUserList} ->
                    lists:keydelete(Username, 2, UpdatedUserList),
                    %io:format("Current online user(s): ~p~n", [UpdatedUserList]),
                    logic_handler(Username, UpdatedUserList, GroupList);
                {updated_group_list, UpdatedGroupList} ->
                    %io:format("Available group chat: ~p~n", [UpdatedGroupList]),
                    logic_handler(Username, UserList, UpdatedGroupList);
                {updated_group_member_join, NewMember} ->
                    %io:format("~p just joined the conversation~n", [NewMember]);
                    logic_handler(Username, UserList, GroupList);
                {updated_group_member_leave, Username} ->
                    %io:format("~p just left the conversation~n", [Username]);
                    logic_handler(Username, UserList, GroupList);
                _ ->
                    unknown_broadcast_message,
                    logic_handler(Username, UserList, GroupList)
            end;

        % broadcast message received from other users
        {bc_receive, Message, Sender} ->
            app_layer ! {bc_receive, Message, Sender},            
            logic_handler(Username, UserList, GroupList);

        %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
        % send a direct message to another user
        {msg_send, RecipientUsn, Msg} ->
            % retrieve user process id from UserList
            client_pid ! {RecipientUsn, Msg},
            logic_handler(Username, UserList, GroupList);

        % broadcast message
        {msg_broadcast, Message} ->            
            %broadcast(Msg, UserList, Username), 
            client_pid ! {message_out, broadcast, Message},
            logic_handler(Username, UserList, GroupList);


        {msg_receive, _RecipientUsn, Msg, SenderUsn, SenderPid} ->
            % when receiving a message sent by another
            io:format("~w: ~p~n", [SenderUsn, Msg]),
            %log system works here to record into Riak later
            logic_handler(Username, UserList, GroupList);

        % TODO: seperate from application layer
        client_connect ->
            pass;

        client_disconnect ->
             client_pid ! {{self(), client_disconnected}, [{chat_server, server_node()}]},
            unregister(logic_layer);

        %%%%%%%%%%%%%%%%% GROUP %%%%%%%%%%%%%
        % request to create group (group name, description)
        {group_create_req, GroupName, GroupDescription} ->
            client_pid ! {{group_server, server_node()}, {group_create_req, GroupName, GroupDescription, Username, self()}},
            logic_handler(Username, UserList, GroupList);

        {group_create_res, GroupName, UpdatedGroupList} ->
            % print out the name
            %io:format("Group ~p has been created!~n", [GroupName]),
            io:format("Available chat groups: ~p~n", [UpdatedGroupList]),
            logic_handler(Username, UserList, GroupList);

        % request to join an existing group
        {group_join_req, GroupName} ->
            client_pid ! {message_out, {group_server, server_node()}, {group_join_req, GroupName, Username, self()}},
            logic_handler(Username, UserList, GroupList);

        %
        {group_join_res, UpdatedGroupList, [NewMember|Others]} ->
            io:format("Updated group info: ~p~n", UpdatedGroupList),            
            BCMessage = {updated_group_member, NewMember},
            broadcast(BCMessage, Others),
            logic_handler(Username, UserList, GroupList);            


        % request to leave an existing group of which one is member
        {group_leave_req, GroupName} ->
            % send it down to lower layer
            client_pid ! {{group_server, server_node()}, group_leave_req, GroupName, Username, self()},
            logic_handler(Username, UserList, GroupList);

        group_list_req ->
            % io:format("Available groups: ~p~n!", [Group_list]),
            % logic_handler(Username, User_list, Group_list)
            client_pid ! {{group_server, server_node()}, group_list_req, self()},
            logic_handler(Username, UserList, GroupList);

        {group_leave_res, UpdatedGroupList, UpdatedMemberList, Username} ->
            BCMessage = {updated_group_member, Username},
            broadcast(BCMessage, UpdatedMemberList),
            logic_handler(Username, UserList, GroupList);

        {group_broadcast_req, GroupName, Message} ->
            case lists:keysearch(GroupName, 1, GroupList) of
                false ->
                    no_such_group,
                    logic_handler(Username, UserList, GroupList);
                {value, {Name, Desc, Starter, MemberList}} ->
                    broadcast(Message, MemberList, Username),            
                    logic_handler(Username, UserList, GroupList)
            end 


        % {group_list_res, Message} ->
        %     io:format("Available chat groups: ~n", [Message]),
        %     logic_handler(Username, UserList, Group_list)

                  

    end.

% broadcast(Msg, User_list, Sender) ->
%     [Pid ! {bc_receive, Msg, Sender} || {Pid, Username} <- User_list].
% broadcast(Msg, User_list) ->
%     [Pid ! {bc_receive, Msg} || {Pid, Username} <- User_list].


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%% TRANSMISSION LAYER %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

%%% Involve logical dispatching
transmission_handler(Username, UserList) ->
    receive
        {message_out, Rcpt, Message} ->
            case
            Rcpt ! {message_in, Message, self()},
            transmission_handler(Username, UserList);

        {message_in, Message, Sender} ->
            logic_layer ! {message_in, Message, Sender};

        % Message = {Pid, Usersname}
        {broadcast_send, UserList, Message, Sender} -> %send message to all nodes connected
            broadcast(Message, UserList),
            transmission_handler(Username, UserList);
        {unicast, Node, Message} -> % send message to 1 specific node
            sent,
            transmission_handler(Username, UserList)
    end.

broadcast(Message, UserList) ->
    [Pid ! {bc_receive, Message} || {Pid, Username} <- UserList].
broadcast(Msg, User_list, Sender) ->
    [client_pid ! {Username, bc_receive, Msg} || {Pid, Username} <- User_list].

username_lookup(Username, UserList) ->
    case lists:keysearch(Username, 2, UserList) of
        false -> % nothing found
            username_not_found;
        {value, {Pid, Username}} -> % tuple returned
            %io:format("Send message ~w to user ~w with pid ~w~n", [Msg, RcptUsn, RcptPid]),
            %RcptPid ! {msg_receive, RcptUsn, Msg, Username, self()}
            {Pid, Username}
    end.
