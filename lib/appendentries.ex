
# distributed algorithms, n.dulay, 8 feb 2022
# coursework, raft consensus, v2

defmodule AppendEntries do

# s = server process state (c.f. this/self)

 # ... omitted
 def receive_append_entries_timeout(s, mterm) do
    for peer <- s.servers do
      send peer, {:HEART_BEAT, mterm, nil }
    end
    s |> Timer.restart_append_entries_timer()
 end

end # AppendEntriess
