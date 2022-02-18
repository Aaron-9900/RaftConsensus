defmodule AppendEntriesTest do
  use ExUnit.Case
  doctest Cw1
# PARA MAÑANA: SI POR DETRAS, HACER + PETICIONES. SI TIENE ALGUNAS EXTRA, ELIMINARLAS.
# ADEMÁS, CONSIDERAR ULTIMA ENTRY EN LEADERSHIP ELECTION
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
        monitorP: monitor,
        die_after:  1000000..1000000,
        die_after_time:  1000000..1000000
    },
    client_config: %{
      client_request_interval: 1,
      n_accounts: 2,
      max_amount: 100,
      max_client_requests: 10,
      client_reply_timeout: 200,
      client_timelimit: 2000,
      debug_options:  "",
      die_after:  1000000..1000000,
      die_after_time:  1000000..1000000
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

    # Make me leader -------------------------------------------
    send node, {:VOTE_REQUEST, 1, %{curr_election: 1, selfP: self(), candidate_number: 0, server_num: -1, log: log}}
    assert_receive {:VOTE_REPLY, _mterm, m}, 600
    assert m.value

    # Receive client request ------------------------------------
    assert_receive { :CLIENT_REQUEST, msg }, 100
    # Send append entry --------------------------------
    self_config = %{log: log, term: 1, next_index: %{}, selfP: self(),
        commit_index: 0, append_entries_timers: %{}, test: true, curr_term: 0}
    self_config = Map.put(self_config, :config, state.server_config)
    AppendEntries.send_append_entries_request(self_config, 1, node)

    assert_receive {:APPEND_ENTRIES_REPLY, mterm, m }, 100
    assert m.result
    assert m.ack == 1

  end

end
