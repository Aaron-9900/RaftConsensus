defmodule VoteTest do
  use ExUnit.Case
  doctest Cw1

  setup do
      {:ok, config:
        %{ node_suffix: 0,
          raft_timelimit: 0,
          debug_level:    0,
          debug_options:  "",
          n_servers:      1,
          n_clients:      0,
          election_timeout_range:  100..200, # timeout(ms) for election, set randomly in range}
          append_entries_timeout:  10,       # timeout(ms) for the reply to a append_entries request
          die_after:  1000000..1000000,
          die_after_time:  1000000..1000000
      }
    }

  end

  test "node should send vote request", state do
    config = state[:config]
    node = spawn(Server, :start, [config, 1])
    send node, {:BIND, [self()], nil}

    assert_receive {:VOTE_REQUEST, _mterm, m}, 300
    assert m.selfP == node
  end

  test "should vote candidate", state do
    config = state.config
    node = spawn(Server, :start, [config, 1])
    send node, {:BIND, [self()], nil}

    send node, {:VOTE_REQUEST, 1, %{curr_election: 1, selfP: self(), candidate_number: 0, server_num: -1, log: %{}}}
    assert_receive {:VOTE_REPLY, _mterm, m}, 600
    assert m.value
    assert m.curr_election == 1
    assert m.selfP == node
    assert m.role == :FOLLOWER

  end

  test "should not vote candidate if already voted", state do
    config = state.config |> Map.put(:n_servers, 3)
    node1 = spawn(Server, :start, [Map.put(config, :election_timeout_range, 80..81), 1])
    node2 = spawn(Server, :start, [config, 2])
    send node1, {:BIND, [self(), node1, node2], nil}
    send node2, {:BIND, [self(), node1, node2], nil}

    assert_receive {:VOTE_REQUEST, mterm, m}, 300
    assert m.selfP == node1
    Process.sleep(5)
    send node2, {:VOTE_REQUEST, 1, %{curr_election: 1, selfP: self(), candidate_number: 0, server_num: -1, log: %{}}}
    assert_receive {:VOTE_REPLY, _mterm, m}, 600
    assert !m.value
    assert m.selfP == node2
    assert m.role == :FOLLOWER
  end
  @tag :wip
  test "should not vote candidate if already candidate", state do
    config = state.config |> Map.put(:n_servers, 3)
    node1 = spawn(Server, :start, [Map.put(config, :election_timeout_range, 80..81), 1])
    send node1, {:BIND, [self(), node1], nil}

    assert_receive {:VOTE_REQUEST, _mterm, m}, 300
    assert m.selfP == node1

    send node1, {:VOTE_REQUEST, 1, %{curr_election: 1, selfP: self(), candidate_number: 0, server_num: -1, log: %{}}}

    assert_receive {:VOTE_REPLY, _mterm, m}, 600

    assert !m.value
    assert m.selfP == node1
    assert m.role == :CANDIDATE
  end

  test "gains leadership with majority of votes", state do
    config = state.config |> Map.put(:n_servers, 3)
    node1 = spawn(Server, :start, [Map.put(config, :election_timeout_range, 80..81), 1])
    node2 = spawn(Server, :start, [config, 2])
    send node1, {:BIND, [self(), node1, node2], nil}
    send node2, {:BIND, [self(), node1, node2], nil}

    assert_receive {:VOTE_REQUEST, _mterm, m}, 300
    assert m.selfP == node1

    send node1, {:VOTE_REPLY, 0, %{value: false, selfP: self(), curr_election: 1, server_num: -1, log: %{}}}

    assert_receive {:APPEND_ENTRIES_REQUEST, 1, m}

    assert m.leaderP == node1
  end

  test "has no leadership without majority and resends", state do
    config = state.config |> Map.put(:n_servers, 3)
    node1 = spawn(Server, :start, [Map.put(config, :election_timeout_range, 80..81), 1])
    send node1, {:BIND, [self(), node1], nil}

    assert_receive {:VOTE_REQUEST, _mterm, m}, 300

    send node1, {:VOTE_REPLY, 0, %{value: false, selfP: self(), curr_election: 1, server_num: -1, log: %{}}}

    assert_receive {:VOTE_REQUEST, _mterm, m}, 300

    assert m.role == :CANDIDATE
    assert m.selfP == node1

  end

  test "discards old election requests", state do
    config = state.config |> Map.put(:n_servers, 3)
    node1 = spawn(Server, :start, [Map.put(config, :election_timeout_range, 80..81), 1])
    send node1, {:BIND, [self(), node1], nil}

    assert_receive {:VOTE_REQUEST, _mterm, m}, 300

    send node1, {:VOTE_REPLY, 0, %{value: false, selfP: self(), curr_election: 1, server_num: -1, log: %{}}}

    assert_receive {:VOTE_REQUEST, _mterm, m}, 300

    send node1, {:VOTE_REPLY, 1, %{value: true, selfP: self(), curr_election: 1, server_num: -1, log: %{}}}

    assert_receive {:VOTE_REQUEST, _mterm, m}, 300

  end

  test "can gain leadership after losing", state do
    config = state.config |> Map.put(:n_servers, 3)
    node1 = spawn(Server, :start, [Map.put(config, :election_timeout_range, 80..81), 1])
    send node1, {:BIND, [self(), node1], nil}

    assert_receive {:VOTE_REQUEST, _mterm, m}, 300

    send node1, {:VOTE_REPLY, 1, %{value: false, selfP: self(), curr_election: 1, server_num: -1}}

    assert_receive {:VOTE_REQUEST, _mterm, m}, 300

    assert m.role == :CANDIDATE
    assert m.selfP == node1

    send node1, {:VOTE_REPLY, 1, %{value: true, selfP: self(), curr_election: 2, server_num: -1}}

    assert_receive {:APPEND_ENTRIES_REQUEST, _, m}

    assert m.leaderP == node1
    assert m.current_term == 2

  end

  test "when leader timeouts, new election starts and leader steps down", state do
    config = state.config |> Map.put(:n_servers, 3)
    node1 = spawn(Server, :start, [Map.put(config, :election_timeout_range, 80..81), 1])
    node2 = spawn(Server, :start, [config, 2])
    send node1, {:BIND, [self(), node1, node2], nil}
    send node2, {:BIND, [self(), node1, node2], nil}

    # ---- Make node 1 leader ------
    assert_receive {:VOTE_REQUEST, _mterm, m}, 300
    assert m.selfP == node1

    send node1, {:VOTE_REPLY, 0, %{value: false, selfP: self(), curr_election: 1, server_num: -1}}

    assert_receive {:APPEND_ENTRIES_REQUEST, 1, m}

    assert m.leaderP == node1
    # Shut down node 1 ---------------
    send node1, { :STOP }
    # Receive new election from node2
    assert_receive {:VOTE_REQUEST, 1, m}, 300
    assert m.selfP == node2
    assert m.curr_election == 2

    send node2, {:VOTE_REPLY, 1, %{value: true, selfP: self(), curr_election: 2, server_num: -1}}
    assert_receive {:APPEND_ENTRIES_REQUEST, 2, m}, 200

  end

end
