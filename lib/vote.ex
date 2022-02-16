
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

def increase_curr_term(s), do: Map.put(s, :curr_term, s.curr_term + 1)

# voted for someone OR (I'm a candidate AND I'm not voting for myself)
@spec should_not_vote?(any, atom | %{:voted_for => any, optional(any) => any}) :: boolean
def should_not_vote?(s, m), do: s.voted_for != nil || (s.role == :CANDIDATE && s.selfP != m.selfP)


# ... omitted
@spec receive_election_timeout(%{
        :curr_election => number,
        :curr_term => any,
        :server_num => any,
        :servers => any,
        optional(any) => any
      }) :: atom | %{:config => atom | map, optional(any) => any}
def receive_election_timeout(s) do
  msg = { :VOTE_REQUEST, s.curr_term, Map.put(s, :curr_election, s.curr_election + 1)}
  for server <- s.servers do
    send server, msg
  end
  s |> Vote.curr_election(s.curr_election + 1)
    |> Vote.voted_for(nil)
    |> Vote.role(:CANDIDATE)
    |> Vote.voted_by(MapSet.new)
    |> Timer.restart_election_timer()
    |> Debug.message("+vreq", { :VOTE_REQUEST, s.curr_term, %{
      election: s.curr_election + 1,
      candidate_number: s.server_num # For debug only
      } })
end

@spec send_vote_reply_to_candidate(any, atom | pid | port | reference | {atom, atom}, any) :: any
def send_vote_reply_to_candidate(s, m, value) do
  send m.selfP, {:VOTE_REPLY, s.curr_term, Map.put(s, :value, value)}
  s |> Debug.message("+vrep", {s.server_num, m.server_num, value})
end

def receive_vote_request_from_candidate(s, _mterm, m) do
  if s.curr_election == m.curr_election && Vote.should_not_vote? s, m do
    Vote.send_vote_reply_to_candidate(s, m, false)
  else
    s |> Vote.curr_election(m.curr_election)
      |> Vote.voted_for(m.selfP)
      |> Vote.role(m, :FOLLOWER)
      |> Vote.send_vote_reply_to_candidate(m, true)
      |> Timer.restart_election_timer()
  end
end

def receive_vote_reply_from_follower(s, _mterm, m) do
  if !MapSet.member?(s.voted_by, m.selfP) && m.value do
    s |> Vote.voted_by(m.selfP)
      |> Vote.maybe_leader()
      |> Vote.initialize_heartbeat_timer()
      |> Debug.message("-vrep", {s.server_num, m.server_num,  State.vote_tally(s)})
  else
    s
  end
end

def initialize_multiple_timers(s, peers) when length(peers) == 1 do
    s |>  Timer.restart_append_entries_timer(hd(peers))
end

def initialize_multiple_timers(s, peers) do
  s |> Vote.restart_append_entries_timer_if_not_self(hd(peers))
    |> Vote.initialize_multiple_timers(tl(peers))
end

def restart_append_entries_timer_if_not_self(s, peer) do
  if s.selfP != peer do
    s |> Timer.restart_append_entries_timer(peer)
  else
    s
  end
end
def initialize_heartbeat_timer(s) do
  if s.role == :LEADER do
    s |>  Vote.initialize_multiple_timers(s.servers)
  else
    s
  end
end

@spec maybe_leader(atom | %{:majority => any, :voted_by => map, optional(any) => any}) ::
        atom | map
def maybe_leader(s) do
  if State.vote_tally(s) > s.majority do
    s |> Vote.role(:LEADER)
      |> Vote.leader(s.selfP)
      |> Timer.cancel_election_timer()
      |> Vote.increase_curr_term()
  else
    s
  end
end


end # Vote
