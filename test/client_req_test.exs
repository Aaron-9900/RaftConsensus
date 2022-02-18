defmodule ClientReqTest do
  use ExUnit.Case
  doctest Cw1

  setup do
    {:ok, server_config:
      %{ node_suffix: 0,
        raft_timelimit: 0,
        debug_level:    0,
        debug_options:  "",
        n_servers:      1,
        n_clients:      0,
        election_timeout_range:  100..200, # timeout(ms) for election, set randomly in range}
        append_entries_timeout:  10 ,      # timeout(ms) for the reply to a append_entries request
        die_after:  1000000..1000000,
        die_after_time:  1000000..1000000
    },
    client_config: %{
      client_request_interval: 5,
      n_accounts: 2,
      max_amount: 100,
      max_client_requests: 10,
      client_reply_timeout: 200,
      client_timelimit: 1000,
      debug_options:  "",
      die_after: 1000000..1000000,
      die_after_time: 1000000..1000000
    }
  }

end
  test "client sends request to nodes", state do
    client = spawn(Client, :start, [state.client_config, 1, [self()]])

    assert_receive({ :CLIENT_REQUEST, msg })
    assert msg.clientP == client

  end

end
