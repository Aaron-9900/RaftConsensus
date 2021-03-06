
# Aaron Hoffman (aah21)
# coursework, raft consensus, v2

defmodule ClientReq do

# s = server process state (c.f. self/this)

# omitted

@spec receive_request_from_client(atom | %{:servers => any, optional(any) => any}, any) :: no_return
def receive_request_from_client(s, m) do
  if s.role == :LEADER do
    s |> ClientReq.append_entry_if_new(m)
  else
    s |> ClientReq.reply_with_leader(m)
  end
end

def append_entry_if_new(s, m) do
  {client, id} = m.cid
  cond do
    s.seen_client_requests[client] == nil || !MapSet.member?(s.seen_client_requests[client], id) ->
      s |> State.seen_client_requests(client, id)
        |> Log.append_entry(Map.put(m, :term, s.curr_term))
        # |> ClientReq.sleep_if_max_seen()
        |> ClientReq.send_request_to_monitor()
        |> State.processed_requests(s.processed_requests + 1)
     true -> s
    end
end

def sleep_if_max_seen(s) do
  if s.processed_requests > s.config.max_requests_to_die do
    Process.sleep(500)
    Server.flush()
    s |> State.processed_requests(0)
  else
    s
  end
end

def send_request_to_monitor(s) do
  send s.config.monitorP, { :CLIENT_REQUEST, s.server_num }
  s
end

def reply_with_leader(s, m) do
  send m.clientP, { :CLIENT_REPLY, m.cid, :NOT_LEADER, s.leaderP }
  s |> Debug.message("+creq", { :CLIENT_REPLY, m.cid, :NOT_LEADER, s.leaderP })
end

def reply_to_client_with_result(s, m) do
  if s.role == :LEADER do
    send m.clientP, { :CLIENT_REPLY, m.cid, true, s.selfP }
    s |> Debug.message("+crep", m)
  end
  s
end


end # Clientreq
