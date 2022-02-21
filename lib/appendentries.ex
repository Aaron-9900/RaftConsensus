
# Aaron Hoffman (aah21)
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
   s  |> Debug.message("+areq", {Map.put(msg, :to, followerP), s.log})
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
      Debug.message(s, "-areq", {m, s.log})
   end

   valid_operation = cond do
      m.current_term < s.curr_term -> false
      m.sent_from_idx <= 1 -> true
      Log.last_index(s) >= m.sent_from_idx - 1 && Log.term_at(s, m.sent_from_idx - 1) == m.prev_log_term  ->
         true
      true -> false
   end
    s |> AppendEntries.append_entries_if_valid(m, mterm, valid_operation)
      |> AppendEntries.commit_leader_entries(m.leader_commit, valid_operation)
      |> AppendEntries.send_append_entries_reply(m, valid_operation)
      |> Timer.restart_election_timer()
 end

 def commit_leader_entries(s, commit_to, valid) do
   if commit_to > s.commit_index && valid do
      Debug.message(s, "+dreqplus", {s.commit_index + 1, commit_to, Log.get_entries(s, (s.commit_index + 1)..commit_to)})
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
      tmp = for entry <- m.entries, reduce: [] do
         acc ->
         {k, v} = entry
         if Log.entry_at(s, k) != nil && Log.term_at(s, k) != v.term do
            [k | acc]
         else
            acc
         end
      end
      if Enum.count(tmp) > 0 do
         t = Log.get_entries(s, Enum.min(tmp)..Log.last_index(s))

         s |> State.remove_seen_client_requests(t)
           |> Log.delete_entries_from(Enum.min(tmp))
           |> Debug.message("-areq", "Deleting entries from #{Enum.min(tmp)}")
      else
         s
      end
   else
      s
   end
   s = for entry <- m.entries, reduce: s do
      acc ->
         {_, value} = entry
         {c, id} = value.cid
         State.seen_client_requests(acc, c, id)
   end
   if valid && Enum.count(m.entries) > 0 && Enum.count(m.entries) + m.sent_from_idx - 1 > Log.last_index(s) do
      Log.merge_entries(s, m.entries)
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
            |> Debug.message("-arep", "Retrying: server #{m.sender.server_num} log is older. Sending next index at: #{s.next_index[m.sender.selfP]}. Log is: #{inspect m.sender.log}")

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
   ready = for i <- s.commit_index..Log.last_index(s), n_ack_entries(s, i) >= s.majority do
      i
   end
   ready = AppendEntries.max_ready_to_commit(ready)

   if ready > 0 && ready > s.commit_index && Log.term_at(s, ready) == s.curr_term do
      Debug.message(s, "+dreqplus", {s.commit_index + 1, ready, Log.get_entries(s, (s.commit_index + 1)..ready)})
      for i <- (s.commit_index + 1)..ready do
         send s.databaseP, { :DB_REQUEST, Log.entry_at(s, i) }
         Debug.message(s, "+dreq", {Log.entry_at(s, i).cmd, s.log})
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
