
# distributed algorithms, n.dulay, 8 feb 2022
# coursework, raft consensus, v2

defmodule AppendEntries do

# s = server process state (c.f. this/self)

 # ... omitted
 def receive_append_entries_timeout(s, mterm, followerP) do

    send followerP, {:HEART_BEAT, mterm, s }
    s |> Timer.restart_append_entries_timer(followerP)
 end

 def send_append_entries_request_to_peers(s) do
  for peer <- s.servers do
   if peer != s.selfP do
      sent_from_idx = Map.get(s.next_index, peer, 0) + 1
      entries_to_send = Log.get_entries(s, sent_from_idx..Log.last_index(s))
      prev_log_term = if sent_from_idx > 1 do
         Log.term_at(s, sent_from_idx - 1)
      else
         1
      end
      msg = %{
         entries: entries_to_send,
         prev_log_term: prev_log_term,
         leaderP: s.selfP,
         current_term: s.curr_term,
         sent_from_idx: sent_from_idx,
         leader_commit: s.commit_index
      }
      send peer, {:APPEND_ENTRIES_REQUEST, s.curr_term, msg}
   else
      nil
   end
  end
  s
end
 def receive_append_entries_request_from_leader(s, mterm, m) do
   valid_operation = if m.sent_from_idx > 1 do
      if Log.last_index(s) >= m.sent_from_idx - 1 && Log.term_at(s, m.sent_from_idx - 1) == m.prev_log_term do
         true # Not first entry and prev_term matches
      else
         false
      end
   else
      true # First entry should always be valid...right?
   end

    s |> AppendEntries.append_entries_if_valid(m, mterm, valid_operation)
      |> AppendEntries.commit_leader_entries(m.leader_commit)
      |> AppendEntries.send_append_entries_reply(m, valid_operation)
 end

 def commit_leader_entries(s, commit_to) do
   if commit_to > s.commit_index do
      IO.puts "AAAA #{s.server_num} -- #{commit_to}, #{s.commit_index}"
      for i <- (s.commit_index + 1)..(commit_to) do
         send s.databaseP, { :DB_REQUEST, Log.entry_at(s, i) }
      end
      s |> State.commit_index(commit_to)
   else
      s
   end
 end

 @spec append_entries_if_valid(any, any, any, any) :: any
 def append_entries_if_valid(s, m, _mterm, valid) do
   if valid do
      Enum.reduce(m.entries, s, fn(entry, acc) ->
         {_, value} = entry
         Log.append_entry(acc, value)
      end)
   else
      s
   end
 end

 @spec receive_append_entries_reply_from_follower(
         atom | map,
         any,
         atom | %{:result => any, optional(any) => any}
       ) :: atom | %{:config => atom | map, optional(any) => any}
 def receive_append_entries_reply_from_follower(s,_mterm, m) do
   if m.result do
      s |> State.next_index(m.sender.selfP, m.ack)
        |> Debug.message("-arep", "Reply received")
        |> AppendEntries.commit_entries()
   else # TODO
      s |> Debug.message("-arep", "Follower replied false")
   end
 end

 @spec n_ack_entries(atom | %{:servers => any, optional(any) => any}, any) :: non_neg_integer
 def n_ack_entries(s, len) do
   filtered = Enum.filter(s.servers, fn(server) ->
      s.next_index[server] >= len
   end)
   Enum.count(filtered)
 end

 @spec commit_entries(
         atom
         | %{
             :config => atom | %{:debug_options => binary, optional(any) => any},
             :log => map,
             optional(any) => any
           }
       ) :: atom | %{:config => atom | map, optional(any) => any}
 def commit_entries(s) do
   ready = 1..Log.last_index(s)
            |> Enum.filter(fn(i) ->
               n_ack_entries(s, i) >= s.majority
            end)
            |> Enum.max()
   if ready > s.commit_index && Log.term_at(s, ready) == s.curr_term do
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
   msg = %{ result: valid, sender: s, ack: Enum.count(m.entries) + m.sent_from_idx - 1 }
   send s.leaderP, {:APPEND_ENTRIES_REPLY, s.curr_term, msg}
   s |> Debug.message("+arep", {:APPEND_ENTRIES_REPLY, s.curr_term, %{ result: valid, ack: Enum.count(m.entries) + m.sent_from_idx }})
 end

end # AppendEntriess
