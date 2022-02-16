
# distributed algorithms, n.dulay, 8 feb 2022
# coursework, raft consensus, v2

defmodule ClientReq do

# s = server process state (c.f. self/this)

# omitted

@spec receive_request_from_client(atom | %{:servers => any, optional(any) => any}, any) :: no_return
def receive_request_from_client(s, m) do
  if s.role == :LEADER do
    s |> Log.append_entry(Map.put(m, :term, s.curr_term))
      |> ClientReq.send_request_to_monitor()
  else
    s |> ClientReq.reply_with_leader(m)
  end
end

def send_request_to_monitor(s) do
  send s.config.monitorP, { :CLIENT_REQUEST, s.server_num }
  s
end

@spec reply_with_leader(
        atom
        | %{
            :config => atom | %{:debug_options => binary, optional(any) => any},
            :leaderP => any,
            optional(any) => any
          },
        atom
        | %{
            :cid => any,
            :clientP => atom | pid | port | reference | {atom, atom},
            optional(any) => any
          }
      ) :: atom | %{:config => atom | map, optional(any) => any}
def reply_with_leader(s, m) do
  send m.clientP, { :CLIENT_REPLY, m.cid, :NOT_LEADER, s.leaderP }
  s |> Debug.message("+creq", { :CLIENT_REPLY, m.cid, :NOT_LEADER, s.leaderP })
end

def reply_to_client_with_result(s, m) do
  send m.clientP, { :CLIENT_REPLY, m.cid, true, s.selfP }
  s
end


end # Clientreq
