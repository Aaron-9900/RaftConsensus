
# distributed algorithms, n.dulay, 8 feb 2022
# coursework, raft consensus, v2

defmodule Server do

# s = server process state (c.f. self/this)

# _________________________________________________________ Server.start()
def start(config, server_num) do

  config = config
    |> Configuration.node_info("Server", server_num)
    |> Debug.node_starting()

  receive do
  { :BIND, servers, databaseP } ->
    State.initialise(config, server_num, self(), servers, databaseP)
      |> Timer.restart_election_timer()
      |> Timer.reset_kill_timer()
      |> Server.next()
  end # receive
end # start

# _________________________________________________________ next()
@spec next(atom | %{:curr_election => any, :curr_term => any, optional(any) => any}) :: any
def next(s) do
  s = s |> AppendEntries.commit_entries()

  curr_term = s.curr_term                          # used to discard old messages
  curr_election = s.curr_election                  # used to discard old election timeouts
  s = receive do

  # ________________________________________________________
  { _mtype, mterm, _m } = msg when mterm < curr_term ->     # Discard any other stale messages
    s |> Debug.received("stale #{inspect msg}")

#  { :APPEND_ENTRIES_REQUEST, mterm, m } when mterm < curr_term -> # Reject send Success=false and newer term in reply
#  s |> Debug.message("-areq", "stale #{mterm} #{inspect m}")
#   |> AppendEntries.send_entries_reply_to_leader(m.leaderP, false)

  { :APPEND_ENTRIES_REQUEST, mterm, m } ->            # Leader >> All
    s |> AppendEntries.receive_append_entries_request_from_leader(mterm, m)

  { :APPEND_ENTRIES_REPLY, mterm, m } ->              # Follower >> Leader
    s |> AppendEntries.receive_append_entries_reply_from_follower(mterm, m)
      # |> Server.execute_committed_entries()

  { :APPEND_ENTRIES_TIMEOUT, mterm, followerP } = msg ->   # Leader >> Leader
    s |> Debug.message("-atim", msg)
      |> AppendEntries.receive_append_entries_timeout(mterm, followerP)

    { :DB_REPLY, {:OK, m} } ->
      s |> ClientReq.reply_to_client_with_result(m)


  # ________________________________________________________

  { :VOTE_REQUEST, mterm, m } when mterm < curr_term ->     # Reject, send votedGranted=false and newer_term in reply
  s |> Debug.message("-vreq", "stale #{mterm} #{inspect m}")
    |> Vote.send_vote_reply_to_candidate(m, false)

  { :VOTE_REQUEST, mterm, m } ->                      # Candidate >> All
    s |> Debug.message("-vreq", {m.selfP, m.server_num, s.curr_election, m.curr_election, m.log})
      |> State.leaderP(nil)
      |> Vote.receive_vote_request_from_candidate(mterm, m)

  { :VOTE_REPLY, mterm, m } ->                        # Follower >> Candidate
    if m.curr_election < curr_election do
      s |> Debug.received("Discard Reply to old Vote Request #{inspect m.selfP}, #{mterm}")
    else
      s |> Vote.receive_vote_reply_from_follower(mterm, m)
    end # if

  # ________________________________________________________
  { :ELECTION_TIMEOUT, _mterm, melection } = msg when melection < curr_election ->
    s |> Debug.received("Old Election Timeout #{inspect msg}")

  { :ELECTION_TIMEOUT, _mterm, _melection } = msg ->        # Self {Follower, Candidate} >> Self
    s |> Debug.received("-etim", msg)
      |> Vote.receive_election_timeout()

  # ________________________________________________________
  { :CLIENT_REQUEST, m } = msg ->                           # Client >> Leader
    s |> Debug.message("-creq", msg)
      |> ClientReq.receive_request_from_client(m)

  { :STOP } -> # For testing purposes
    s |> Server.kill_server()

  # { :DB_RESULT, _result } when false -> # don't process DB_RESULT here

  unexpected ->
    Helper.node_halt("************* Server: unexpected message #{inspect unexpected}")

  end # receive

  Server.next(s)
end # next

def stop_sleep(s, time) do
  Process.sleep(time)
  s
end
def flush() do
  receive do
          _ -> flush()
  after
          0 -> nil
  end
end
def kill_server(s) do
  s = s |> State.processed_requests(0)
    |> Debug.message("-died", "Process #{s.server_num} died")
    |> Timer.cancel_all_append_entries_timers()
  Process.sleep(Enum.random(s.config.die_after_time))
  flush()
  s |> Timer.reset_kill_timer()
    |> Debug.message("+died", "Process #{s.server_num} revived")

end

end # Server
