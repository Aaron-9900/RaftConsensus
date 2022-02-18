
# distributed algorithms, n.dulay, 8 feb 2022
# coursework, raft consensus, v2

defmodule Vote do

def curr_election(s, v), do: Map.put(s, :curr_election, v)

def role(s, m, :FOLLOWER) do
  if s.selfP != m.selfP do
    Map.put(s, :role, :FOLLOWER)
  else
    s
  end
end

def role(s, v), do: Map.put(s, :role, v)

def leader(s, v), do: Map.put(s, :leaderP, v)

def voted_for(s, v), do: Map.put(s, :voted_for, v)

def voted_by(s, v), do: Map.put(s, :voted_by, MapSet.put(s.voted_by, v))

@spec is_leader(atom | %{:leaderP => any, :selfP => any, optional(any) => any}) :: boolean
def is_leader(s), do: s.leaderP == s.selfP

def new_voted_by(s),      do: Map.put(s, :voted_by, MapSet.new)

def increase_curr_term(s), do: Map.put(s, :curr_term, s.curr_term + 1)

# invalid log AND (voted for someone OR (I'm a candidate AND I'm not voting for myself))
def should_not_vote?(s, m) do
  valid_log = cond do
    Log.last_term(m) > Log.last_term(s) ->
      true
    Log.last_term(m) == Log.last_term(s) && Log.last_index(s) <= Log.last_index(m) ->
      true
    true -> false
  end
  !valid_log || (s.voted_for != nil || (s.role == :CANDIDATE && s.selfP != m.selfP))
end


# ... omitted
@spec receive_election_timeout(%{
        :curr_election => number,
        :curr_term => any,
        :server_num => any,
        :servers => any,
        optional(any) => any
      }) :: atom | %{:config => atom | map, optional(any) => any}
def receive_election_timeout(s) do
  s = s |> Vote.curr_election(s.curr_election + 1)
    |> Vote.voted_for(nil)
    |> Vote.role(:CANDIDATE)
    |> Vote.new_voted_by()
    |> Timer.restart_election_timer()
    |> Debug.message("+vreq", { :VOTE_REQUEST, s.curr_term, %{
      election: s.curr_election + 1,
      candidate_number: s.server_num # For debug only
      } })
  msg = { :VOTE_REQUEST, s.curr_term, Map.put(s, :curr_election, s.curr_election)}
      for server <- s.servers do
        send server, msg
      end
  s
end

@spec send_vote_reply_to_candidate(any, atom | pid | port | reference | {atom, atom}, any) :: any
def send_vote_reply_to_candidate(s, m, value) do
  send m.selfP, {:VOTE_REPLY, s.curr_term, Map.put(s, :value, value)}
  s |> Debug.message("+vrep", {s.server_num, m.server_num, value})
end

def change_role_if_not_self(s, m) do
  cond do
    s.selfP == m.selfP -> s
    s.selfP != m.selfP -> s |> Vote.role(m, :FOLLOWER)
  end
end

def receive_vote_request_from_candidate(s, mterm, m) do
  if s.curr_election == m.curr_election && Vote.should_not_vote? s, m do
    Vote.send_vote_reply_to_candidate(s, m, false)
  else
    s |> Vote.curr_election(m.curr_election)
      |> Vote.voted_for(m.selfP)
      |> State.curr_term(mterm)
      |> Vote.change_role_if_not_self(m)
      |> Vote.send_vote_reply_to_candidate(m, true)
      |> Timer.restart_election_timer()
  end
end

def receive_vote_reply_from_follower(s, mterm, m) do
  cond do
    !MapSet.member?(s.voted_by, m.selfP) && m.value && mterm == s.curr_term ->
      s |> Vote.voted_by(m.selfP)
        |> Vote.maybe_leader()
        |> Vote.initialize_heartbeat_timer()
        |> Debug.message("-vrep", {s.server_num, m.server_num,  State.vote_tally(s)})
    mterm > s.curr_term ->
      s |> State.curr_term(mterm)
        |> State.role(:FOLLOWER)
        |> State.voted_for(nil)
        |> Vote.new_voted_by()
        |> Timer.restart_election_timer()
    true -> s
  end
end

def initialize_multiple_timers(s, peers) when length(peers) == 1 do
    s |> Vote.restart_append_entries_timer_if_not_self(hd(peers))
end

def initialize_multiple_timers(s, peers) do
  s |> Vote.restart_append_entries_timer_if_not_self(hd(peers))
    |> Vote.initialize_multiple_timers(tl(peers))
end

@spec restart_append_entries_timer_if_not_self(atom | %{:selfP => any, optional(any) => any}, any) ::
        atom | map
def restart_append_entries_timer_if_not_self(s, peer) do
  if s.selfP != peer do
    s |> Timer.restart_append_entries_timer(peer)
  else
    s
  end
end
def initialize_heartbeat_timer(s) do
  if s.role == :LEADER do
    s |> Vote.initialize_multiple_timers(s.servers)
  else
    s
  end
end

def maybe_leader(s) do
  if State.vote_tally(s) >= s.majority do
    s |> Vote.role(:LEADER)
      |> Vote.leader(s.selfP)
      |> Timer.cancel_election_timer()
      |> Vote.increase_curr_term()
  else
    s
  end
end


end # Vote
