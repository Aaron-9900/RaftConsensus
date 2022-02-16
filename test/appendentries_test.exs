defmodule AppendEntriesTest do
  use ExUnit.Case
  doctest Cw1

  setup do
    monitor = spawn(Monitor, :start, [%{monitor_interval: 1000000}])
    {:ok, server_config:
      %{ node_suffix: 0,
        raft_timelimit: 0,
        debug_level:    0,
        debug_options:  "",
        n_servers:      3,
        n_clients:      0,
        election_timeout_range:  100..200, # timeout(ms) for election, set randomly in range}
        append_entries_timeout:  10,       # timeout(ms) for the reply to a append_entries request
        monitorP: monitor
    },
    client_config: %{
      client_request_interval: 1,
      n_accounts: 2,
      max_amount: 100,
      max_client_requests: 10,
      client_reply_timeout: 200,
      client_timelimit: 2000,
      debug_options:  "",
    },
    db_config: %{
      monitorP: monitor,
    }
  }

end
  test "node sends append_entries_request when leader", state do
    node = spawn(Server, :start, [state.server_config, 1])
    client = spawn(Client, :start, [state.client_config, 1, [node]])
    db = spawn(Database, :start, [state.db_config, 1])

    send node, {:BIND, [self(), node], db}

    assert_receive {:VOTE_REQUEST, _mterm, m}, 300

    send node, {:VOTE_REPLY, 0, %{value: true, selfP: self(), curr_election: 1, server_num: -1}}

    assert_receive {:APPEND_ENTRIES_REQUEST, 1, _m}, 300

  end

  test "accepts first entry", state do
    node = spawn(Server, :start, [state.server_config, 1])
    client = spawn(Client, :start, [state.client_config, 1, [self()]])
    db = spawn(Database, :start, [state.db_config, 1])
    send node, {:BIND, [self(), node], db}
    log = Log.new()
    self_config = %{log: log}

    # Make me leader -------------------------------------------
    send node, {:VOTE_REQUEST, 1, %{curr_election: 1, selfP: self(), candidate_number: 0, server_num: -1}}
    assert_receive {:VOTE_REPLY, _mterm, m}, 600
    assert m.value
    send node, {:HEART_BEAT, 1, %{selfP: self()}}

    # Receive client request ------------------------------------
    assert_receive { :CLIENT_REQUEST, msg }, 100
    self_config = Log.append_entry(self_config, Map.put(msg, :term, 1))
    # Send append entry --------------------------------
    sent_from_idx = 1
    last_idx = Log.last_index(self_config)
    entries_to_send = Log.get_entries(self_config, sent_from_idx..last_idx)
    prev_log_term = if sent_from_idx > 1 do
       Log.term_at(self_config, sent_from_idx - 1)
    else
       1
    end
    msg = %{
      entries: entries_to_send,
      prev_log_term: prev_log_term,
      leaderP: self(),
      current_term: 1,
      sent_from_idx: sent_from_idx,
   }

    send node, {:APPEND_ENTRIES_REQUEST, 1, msg}
    assert_receive {:APPEND_ENTRIES_REPLY, mterm, m }
    assert m.result
    assert m.ack == 1
    send client, { :CLIENT_REPLY, Log.entry_at(self_config, last_idx).cid, true, self() }

    assert_receive { :CLIENT_REQUEST, msg }, 100
    self_config = Log.append_entry(self_config, Map.put(msg, :term, 1))



  end

end
