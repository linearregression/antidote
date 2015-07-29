%% -------------------------------------------------------------------
%%
%% Copyright (c) 2014 SyncFree Consortium.  All Rights Reserved.
%%
%% This file is provided to you under the Apache License,
%% Version 2.0 (the "License"); you may not use this file
%% except in compliance with the License.  You may obtain
%% a copy of the License at
%%
%%   http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing,
%% software distributed under the License is distributed on an
%% "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
%% KIND, either express or implied.  See the License for the
%% specific language governing permissions and limitations
%% under the License.
%%
%% -------------------------------------------------------------------

%% This vnode is responsible for receiving transactions from remote DCs and
%% passing them on to appropriate buffer FSMs

-module(inter_dc_sub_vnode).
-behaviour(riak_core_vnode).
-include("antidote.hrl").
-include("inter_dc_repl.hrl").

-export([deliver_message/1, start_vnode/1, register_dc/2]).
-export([init/1, handle_command/3, handle_coverage/4, handle_exit/3, handoff_starting/2, handoff_cancelled/1, handoff_finished/2, handle_handoff_command/3, handle_handoff_data/2, encode_handoff_item/2, is_empty/1, terminate/2, delete/1]).

-record(state, {
  partition :: non_neg_integer(),
  buffer_fsms :: dict() %% partition_dcid -> relsub_fsm
}).

register_dc(DCID, LogReaderAddresses) ->
  Request = {add_dc, DCID, hd(LogReaderAddresses)},
  dc_utilities:bcast_vnode_sync(inter_dc_sub_vnode_master, Request),
  ok.

deliver_message(Msg) -> call(Msg#interdc_txn.partition, {txn, Msg}).

init([Partition]) -> {ok, #state{partition = Partition, buffer_fsms = dict:new()}}.
start_vnode(I) -> riak_core_vnode_master:get_vnode_pid(I, ?MODULE).

handle_command({txn, Txn}, _Sender, State) ->
  PDCID = {Txn#interdc_txn.dcid, Txn#interdc_txn.partition},
  {ok, BufferFsm} = dict:find(PDCID, State#state.buffer_fsms),
  {reply, inter_dc_sub_buf_fsm:handle_txn(BufferFsm, Txn), State};

handle_command({add_dc, DCID, Address}, _Sender, State) ->
  PDCID = {DCID, State#state.partition},
  {ok, BufferFsm} = inter_dc_sub_buf_fsm:start_link(PDCID, Address),
  NewState = State#state{buffer_fsms = dict:store(PDCID, BufferFsm, State#state.buffer_fsms)},
  {reply, ok, NewState}.

handle_coverage(_Req, _KeySpaces, _Sender, State) -> {stop, not_implemented, State}.
handle_exit(_Pid, _Reason, State) -> {noreply, State}.
handoff_starting(_TargetNode, State) -> {true, State}.
handoff_cancelled(State) -> {ok, State}.
handoff_finished(_TargetNode, State) -> {ok, State}.
handle_handoff_command(_Message, _Sender, State) -> {noreply, State}.
handle_handoff_data(_Data, State) -> {reply, ok, State}.
encode_handoff_item(_ObjectName, _ObjectValue) -> <<>>.
is_empty(State) -> {true, State}.
terminate(_Reason, _ModState) -> ok.
delete(State) -> {ok, State}.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

call(Partition, Request) -> dc_utilities:call_vnode_sync(Partition, inter_dc_sub_vnode_master, Request).