
# distributed algorithms, n.dulay, 10 jan 22 
# coursework, raft 
# Makefile, v1

SERVERS   = 5      	
CLIENTS   = 5

DIE_AFTER = 2

TIMELIMIT = 15000	# quits after milli-seconds(ms)
SETUP     = default	# one of default, slower, faster, etc

# AppendEntries(areq, arep, atim), Vote(vreq, vrep, vall), Election(etim), DB(dreq, drep), Client(creq, crep)
# Prefixes + for send/send_after,  - for receive
DEBUG_OPTIONS = ""

DEBUG_LEVEL   = 1

START     = Raft.start
HOST	 := 127.0.0.1

# --------------------------------------------------------------------

TIME    := $(shell date +%H:%M:%S)
SECS    := $(shell date +%S)
COOKIE  := $(shell echo $$PPID)

NODE_SUFFIX := ${SECS}_${LOGNAME}@${HOST}

ELIXIR  := elixir --no-halt --cookie ${COOKIE} --name
MIX 	:= -S mix run -e ${START} \
	${NODE_SUFFIX} ${TIMELIMIT} ${DEBUG_LEVEL} ${DEBUG_OPTIONS} \
	${SERVERS} ${CLIENTS} ${SETUP} ${DIE_AFTER}
	
MIX_TEST = mix test

# --------------------------------------------------------------------

run cluster: compile
	@ echo -------------------------------------------------------------------
	@ ${ELIXIR} server1_${NODE_SUFFIX} ${MIX} cluster_wait &
	@ ${ELIXIR} server2_${NODE_SUFFIX} ${MIX} cluster_wait &
	@ ${ELIXIR} server3_${NODE_SUFFIX} ${MIX} cluster_wait &
	@ ${ELIXIR} server4_${NODE_SUFFIX} ${MIX} cluster_wait &
	@ ${ELIXIR} server5_${NODE_SUFFIX} ${MIX} cluster_wait &
	
	@ ${ELIXIR} client1_${NODE_SUFFIX} ${MIX} cluster_wait &
	@ ${ELIXIR} client2_${NODE_SUFFIX} ${MIX} cluster_wait &
	@ ${ELIXIR} client3_${NODE_SUFFIX} ${MIX} cluster_wait &
	@ ${ELIXIR} client4_${NODE_SUFFIX} ${MIX} cluster_wait &
	@ ${ELIXIR} client5_${NODE_SUFFIX} ${MIX} cluster_wait &
	@sleep 5
	@ ${ELIXIR} raft_${NODE_SUFFIX} ${MIX} cluster_start
compile:
	mix compile

clean:
	mix clean
	@rm -f erl_crash.dump

ps:
	@echo ------------------------------------------------------------
	epmd -names


