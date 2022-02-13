
# distributed algorithms, n.dulay, 8 feb 2022
# coursework, raft consensus, v2

defmodule ClientReq do

# s = server process state (c.f. self/this)

# omitted

@spec receive_request_from_client(atom | %{:servers => any, optional(any) => any}, any) :: no_return
def receive_request_from_client(s, m) do
  for server <- s.servers do
    send server, {:APPEND_ENTRIES_REQUEST, m}
  end
end

end # Clientreq
