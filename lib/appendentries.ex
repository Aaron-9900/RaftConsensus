
# distributed algorithms, n.dulay, 8 feb 2022
# coursework, raft consensus, v2

defmodule AppendEntries do

# s = server process state (c.f. this/self)

 # ... omitted

 def receive_append_entries_timeout(s, mterm, followerP) do
   AppendEntries.send_append_entries_request(s, mterm, followerP)
 end

def send_append_entries_request(s, mterm, followerP) do
   sent_from_idx = Map.get(s.next_index, followerP, 1)
   entries_to_send = if sent_from_idx <= Log.last_index(s) do
         Log.get_entries(s, sent_from_idx..Log.last_index(s))
      else
         %{}
      end
   prev_log_term = if sent_from_idx > 1 do
      Log.term_at(s, sent_from_idx - 1)
   else
      1
   end
   msg = %{
      entries: entries_to_send,
      prev_log_term: prev_log_term,
      leaderP: s.selfP,
      current_term: mterm,
      sent_from_idx: sent_from_idx,
      leader_commit: s.commit_index
   }
   send followerP, {:APPEND_ENTRIES_REQUEST, mterm, msg}
   s  |> Debug.message("+areq", Map.put(msg, :to, followerP))
      |> Timer.restart_append_entries_timer(followerP)
end

 def receive_append_entries_request_from_leader(s, mterm, m) do
   s = cond do
      mterm >= s.curr_term ->
         State.curr_term(s, mterm)
            |> State.leaderP(m.leaderP)
            |> State.role(:FOLLOWER)
            |> State.voted_for(nil)
      mterm < s.curr_term -> s
   end

   if Enum.count(m.entries) > 0 do
      Debug.message(s, "-areq", m)
   end

   valid_operation = cond do
      m.current_term < s.curr_term -> false
      m.sent_from_idx <= 1 -> true
      Log.last_index(s) >= m.sent_from_idx - 1 && Log.term_at(s, m.sent_from_idx - 1) == m.prev_log_term  ->
         true
      true -> false
   end
    s |> AppendEntries.append_entries_if_valid(m, mterm, valid_operation)
      |> AppendEntries.commit_leader_entries(m.leader_commit)
      |> AppendEntries.send_append_entries_reply(m, valid_operation)
      |> Timer.restart_election_timer()
 end

 def commit_leader_entries(s, commit_to) do
   if commit_to > s.commit_index do
      for i <- (s.commit_index + 1)..(commit_to) do
         s |> Debug.message("+dreq",  { :DB_REQUEST, Log.entry_at(s, i), s.commit_index, commit_to, s.log })
         send s.databaseP, { :DB_REQUEST, Log.entry_at(s, i) }
      end
      s |> State.commit_index(commit_to)
   else
      s
   end
 end

 def append_entries_if_valid(s, m, _mterm, valid) do
   s = if Enum.count(m.entries) > 0 && Log.last_index(s) > m.sent_from_idx - 1 do
      if Log.last_term(s) != m.entries[m.sent_from_idx].term do
         s |> Log.delete_entries_from(m.sent_from_idx)
      else
         s
      end
   else
      s
   end

   if valid && Enum.count(m.entries) > 0 && Enum.count(m.entries) + m.sent_from_idx - 1 > Log.last_index(s) do
      for entry <- m.entries, reduce: s do
         acc ->
            {idx, value} = entry
            if Log.entry_at(acc, idx) == nil do
                  Log.append_entry(acc, value)
            else
               acc
            end
      end
   else
      s
   end
 end

 def receive_append_entries_reply_from_follower(s, mterm, m) do
   cond do
      mterm > s.curr_term ->
         s |> State.curr_term(mterm)
           |> State.role(:FOLLOWER)
           |> State.voted_for(nil)
           |> State.new_voted_by()
           |> Debug.message("-arep", "Older term. Stepping down as leader")
      mterm == s.curr_term && s.role == :LEADER && m.result ->
         s  |> State.next_index(m.sender.selfP, m.ack)
            |> Debug.message("-arep", "Correct reply received")
            |> AppendEntries.commit_entries()
      mterm == s.curr_term && s.role == :LEADER && !m.result && s.next_index[m.sender.selfP] > 0 ->
         s  |> State.next_index(m.sender.selfP, s.next_index[m.sender.selfP] - 1)
            |> AppendEntries.send_append_entries_request(mterm, m.sender.selfP)
            |> Debug.message("-arep", "Retrying: server #{m.sender.server_num} log is older. Sending next index at: #{s.next_index[m.sender.selfP]}")

      true -> s |> Debug.message("-arep", "Error -- no condition met in append entries reply: mterm: #{mterm}, curr_term: #{s.curr_term}")
   end
 end

 def n_ack_entries(s, len) do
   filtered = Enum.filter(s.servers, fn(server) ->
      Map.get(s.next_index, server, 1) - 1 >= len
   end)
   Enum.count(filtered)
 end
def max_ready_to_commit(r) do
   if r != nil && length(r) > 0 do
      Enum.max(r)
   else
      0
   end
end
 def commit_entries(s) do
   ready = for i <- 0..Log.last_index(s), n_ack_entries(s, i) >= s.majority do
      i
   end
   ready = AppendEntries.max_ready_to_commit(ready)

   if ready > 0 && ready > s.commit_index && Log.term_at(s, ready) == s.curr_term do
      for i <- (s.commit_index + 1)..ready do
         send s.databaseP, { :DB_REQUEST, Log.entry_at(s, i) }
         Debug.message(s, "+dreq", Log.entry_at(s, i).cmd)
      end
      s |> State.commit_index(ready)
   else
      s
   end
 end
 def send_append_entries_reply(s, m, valid) do
   msg = %{ result: valid, sender: s, ack: Enum.count(m.entries) + m.sent_from_idx }
   send s.leaderP, {:APPEND_ENTRIES_REPLY, s.curr_term, msg}
   if msg.ack > 0 do
      s |> Debug.message("+arep", {:APPEND_ENTRIES_REPLY, s.curr_term, %{ result: valid, ack: Enum.count(m.entries) + m.sent_from_idx - 1 }})
   else
      s
   end
 end

end # AppendEntriess
