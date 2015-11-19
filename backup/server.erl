-module (server).
-export ([start_server/0, user_handler/1, group_handler/1]).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%% SERVER SIDE %%%%%%%%%%%%%%%%%%%%%%%%%%%%


start_server() -> % start chat server
	register(chat_server, spawn(server, user_handler, [[]])),
    % SHOULD THERE BE A GROUP SERVER TO HANDLE GROUP ?
    register(group_server, spawn(server, group_handler, [[]])).

%%% Server should maintain the list of online user
user_handler(User_list) ->
	receive
		% receive a connect request from client
		{From, connect, Name} ->
            Updated_user_list = server_logon(From, Name, User_list),
            io:format("User ~w signed in!~n", [Name]),
            io:format("Current online user(s): ~p~n", [Updated_user_list]),
            % broadcast an updated online user list
            MessageToBroadCast = {updated_user_list, Updated_user_list},
            broadcast(MessageToBroadCast, Updated_user_list),
            %[Pid ! {bc_receive, Updated_user_list} || {Pid, Username} <- Updated_user_list],
            user_handler(Updated_user_list);

         % receives a disconnect request from client
        {From, client_disconnected} ->
            Updated_user_list = server_logoff(From, User_list),
            io:format("User ~w signed out!~n", [From]),
            io:format("Current online user(s): ~p~n", [Updated_user_list]),
            MessageToBroadCast = {updated_user_list, Updated_user_list},
            broadcast(MessageToBroadCast, Updated_user_list),
            %[Pid ! {bc_receive, Updated_user_list} || {Pid, Username} <- Updated_user_list],
            user_handler(Updated_user_list)
	end.


% maintain the group information from users
group_handler(GroupList) ->
    receive
        % request to create a new group with structure
        % {GroupName, GroupDescription, CreatorUsn, [ list of member username]
        {group_create_req, GroupName, GroupDescription, Username, Pid} ->
            % add new group to the list of group
            io:format("Request to create group ~p from ~w~n", [GroupName, Username]),
            MemberList = [{Pid, Username}],
            % may perform name check here
            UpdatedGroupList = [{GroupName, GroupDescription, Username, MemberList} | GroupList],            
            io:format("Available groups: ~p~n", [UpdatedGroupList]),
            % send back to requester
            % TODO: HAVE TO PASS DOWN TO TRANSMIT LAYER
            Pid ! {group_create_res, GroupName, UpdatedGroupList},
            MessageToBroadCast = {updated_group_list, UpdatedGroupList},
            broadcast(MessageToBroadCast, UpdatedGroupList), % ALSO BROADCAST TO ALL USERS
            
            group_handler(UpdatedGroupList);

        % list all available group conversation
        {group_list_req, Pid} ->
            Pid ! {group_list_res, GroupList},
            group_handler(GroupList);


        {group_join_req, GroupName, Username, Pid} ->
            io:format("requested~n"),
            case lists:keysearch(GroupName, 1, GroupList) of
                false ->
                    no_such_group,
                    group_handler(GroupList);
                {value, {Name, Desc, Starter, MemberList}} ->
                    UpdatedMemberList = [{Pid, Username} | MemberList],
                    UpdatedGroup = {GroupName, Desc, Starter, UpdatedMemberList},
                    UpdatedGroupList = lists:keyreplace(Name, 1, GroupList, UpdatedGroup),
                    Pid ! {group_join_res, UpdatedGroupList, UpdatedMemberList},
                    group_handler(UpdatedGroupList)

            end;

        {group_leave_req, GroupName, Username, Pid} ->
            case lists:keysearch(GroupName, 1, GroupList) of
                false ->
                    no_such_group,
                    group_handler(GroupList);
                {value, {Name, Desc, Starter, MemberList}} ->
                    UpdatedMemberList = lists:delete({Pid, Username}, MemberList),
                    UpdatedGroup = {GroupName, Desc, Starter, UpdatedMemberList},
                    UpdatedGroupList = lists:keyreplace(Name, 1, GroupList, UpdatedGroup),
                    Pid ! {group_leave_res, UpdatedGroupList, UpdatedMemberList, Username},
                    group_handler(UpdatedGroupList)

            end            
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

broadcast(Msg, User_list) ->
    [Pid ! {bc_receive, Msg} || {Pid, Username} <- User_list].

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%% TRANSMIT LAYER %%%%%%%%%%%%
message_handler() ->
    receive
        {message_in, Message, Sender} ->
            send_to_logic_layer;

        {messenge_out, Message, Receiver} ->
            send_out
    end.



