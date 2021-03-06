
# distributed algorithms, n.dulay, 8 feb 2022
# coursework, raft consensus, v2

defmodule State do

# s = server process state (c.f. self/this)

# _________________________________________________________ State.initialise()
def initialise(config, server_num, self_pid, servers, databaseP) do
  # initialise state variables for server
  %{
    # _____________________constants _______________________

    config:       config,             # system configuration parameters (from Helper module)
    server_num:	  server_num,         # server num (for debugging)
    selfP:        self_pid,             # server's process id
    servers:      servers,            # list of process id's of servers
    num_servers:  config.n_servers,    # no. of servers
    majority:     div(config.n_servers,2) + 1,  # cluster membership changes are not supported in this implementation

    databaseP:    databaseP,          # local database - used to send committed entries for execution

    # ______________ elections ____________________________
    election_timer:  nil,            # one timer for all peers
    curr_election:   0,              # used to drop old electionTimeout messages and votereplies
    voted_for:	     nil,            # num of candidate that been granted vote incl self
    voted_by:        MapSet.new,     # set of processes that have voted for candidate incl. candidate

    append_entries_timers: Map.new,   # one timer for each follower

    leaderP:        nil,	     # included in reply to client request

    # _______________raft paper state variables___________________

    curr_term:	  0,                  # current term incremented when starting election
    log:          Log.new(),          # log of entries, indexed from 1
    role:         :FOLLOWER,          # one of :FOLLOWER, :LEADER, :CANDIDATE
    commit_index: 0,                  # index of highest committed entry in server's log
    last_applied: 0,                  # index of last entry applied to state machine of server

    next_index:   Map.new,            # foreach follower, index of follower's last known entry+1
    match_index:  Map.new,            # index of highest entry known to be replicated at a follower
    seen_client_requests: Map.new,

    # -------------------TESTING----------------
    processed_requests: 0,
    kill_timer: nil
  }
end # initialise

# ______________setters for mutable variables_______________

# log is implemented in Log module

def leaderP(s, v),        do: Map.put(s, :leaderP, v)
def election_timer(s, v), do: Map.put(s, :election_timer, v)
def curr_election(s, v),  do: Map.put(s, :curr_election, v)
def inc_election(s),      do: Map.put(s, :curr_term, s.curr_election + 1)
def voted_for(s, v),      do: Map.put(s, :voted_for, v)
def new_voted_by(s),      do: Map.put(s, :voted_by, MapSet.new)
def add_to_voted_by(s, v),do: Map.put(s, :voted_by, MapSet.put(s.voted_by, v))
def vote_tally(s),        do: MapSet.size(s.voted_by)
def create_client_seen_set(s, c), do: Map.put(s, :seen_client_requests, Map.put(s.seen_client_requests, c, MapSet.new))
def seen_client_requests(s, c, v) do
  s = if s.seen_client_requests[c] == nil do
    s |> State.create_client_seen_set(c)
  else
    s
  end
  Map.put(s, :seen_client_requests, Map.put(s.seen_client_requests, c, MapSet.put(s.seen_client_requests[c], v)))
end

def remove_seen_client_requests(s, requests) do
  for req <- requests, reduce: s do
    acc ->
      {_, value} = req
      {client, id} = value.cid
      if acc.seen_client_requests[client] == nil do
        acc
      else
        acc |> Map.put(:seen_client_requests,
                      Map.put(acc.seen_client_requests, client, MapSet.delete(s.seen_client_requests[client], id)))
      end
  end
end

def kill_timer(s, t), do: Map.put(s, :kill_timer, t)
def append_entries_timers(s),
                          do: Map.put(s, :append_entries_timers, Map.new)
def append_entries_timer(s, i, v),
                          do: Map.put(s, :append_entries_timers,
                          Map.put(s.append_entries_timers, i, v))

def curr_term(s, v),      do: Map.put(s, :curr_term, v)
def inc_term(s),          do: Map.put(s, :curr_term, s.curr_term + 1)

def role(s, v),           do: Map.put(s, :role, v)
def commit_index(s, v),   do: Map.put(s, :commit_index, v)
def last_applied(s, v),   do: Map.put(s, :last_applied, v)

def next_index(s, v),     do: Map.put(s, :next_index, v)
def next_index(s, i, v),  do: Map.put(s, :next_index, Map.put(s.next_index, i, v))
def match_index(s, v),    do: Map.put(s, :match_index, v)
def match_index(s, i, v), do: Map.put(s, :match_index, Map.put(s.match_index, i, v))

def processed_requests(s, v), do: Map.put(s, :processed_requests, v)

def init_next_index(s) do
  v = Log.last_index(s)+1
  new_next_index = for server <- s.servers, into: Map.new do
    {server, v}
  end
  s |> State.next_index(new_next_index)
end # init_next_index

def init_match_index(s) do
  new_match_index = for server <- s.servers, into: Map.new do {server, 0} end
  s |> State.match_index(new_match_index)
end # init_match_index

end # State
