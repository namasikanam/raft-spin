#define MAX_TERM 3 // 1 to 3
#define MAX_LOG 2 // 0 to 1
#define MAX_SERVER // 1 to 3

#define NIL 10 // a number that won't be used

// message channels
typedef AppendEntry {
    byte term, index, prevLogTerm
};
typedef AppendEntryChannels {
    chan ch[3] = [1] of { AppendEntry };
};
AppendEntryChannels ae_ch[3];

typedef AppendEntryResponse {
    byte term;
    bool success
};
typedef AppendEntryResponseChannels {
    chan ch[3] = [1] of { AppendEntryResponse };
};
AppendEntryResponseChannels aer_ch[3];

typedef RequestVote {
    byte term, lastLogIndex, lastLogTerm
};
typedef RequestVoteChannels {
    chan ch[3] = [1] of { RequestVote };
};
RequestVoteChannels rv_ch[3];

typedef RequestVoteResponse {
    byte term;
    bool voteGranted
};
typedef RequestVoteResponseChannels {
    chan ch[3] = [1] of { RequestVoteResponse };
};
RequestVoteResponseChannels rvr_ch[3];

// global variables
byte leaderCommit = 0; // the max committed index + 1

// The following variables are actually local,
// we move them globally, because SPIN doesn't support
// that represent LTL with local variables.
mtype:State = { leader, candidate, follower };
mtype:State state[3];
byte currentTerm[3];

typedef Logs {
    byte log[2];
};
Logs log[3];

// TOOD: 这个 provided 可能还得再考虑一下
proctype server(byte serverId) provided (leaderCommit < MAX_LOG) {
    state[serverId] = follower;
    byte votedFor = NIL;
    byte commitIndex = 0; // the max committed index + 1
    
    // helpers
    byte i;

    bool votesGranted[3];
    RequestVote rv;
    byte lastLogTerm, lastLogIndex;
    RequestVoteResponse rvr;

    AppendEntry ae;
    AppendEntryResponse aer;

    do // main loop
    :: // timeout
        (state[serverId] == candidate || state[serverId] == follower) ->
            atomic {
                state[serverId] = candidate;
                currentTerm[serverId] = currentTerm[serverId] + 1;

end:            if // end here if currentTerm reach the outside of MAX_TERM
                :: (currentTerm[serverId] <= MAX_TERM) -> skip
                fi

                votedFor = serverId;
                votesGranted[0] = 0; votesGranted[1] = 0; votesGranted[2] = 0;
                votesGranted[serverId] = 1;
            }
    :: // restart
        state[serverId] = follower
    :: // request vote
        (state[serverId] == candidate) ->
            atomic {
                rv.term = currentTerm[serverId];
                if
                :: (log[serverId].log[0] == 0) ->
                    rv.lastLogTerm = 0;
                    rv.lastLogIndex = 0
                :: (log[serverId].log[0] != 0 && log[serverId].log[1] == 0) ->
                    rv.lastLogTerm = log[serverId].log[0];
                    rv.lastLogIndex = 1
                :: (log[serverId].log[0] != 0 && log[serverId].log[1] != 0) ->
                    rv.lastLogTerm = log[serverId].log[1];
                    rv.lastLogIndex = 2
                fi

end:            if
                :: (serverId != 0) ->
                    rv_ch[serverId].ch[0]!rv
                :: (serverId != 1) ->
                    rv_ch[serverId].ch[1]!rv
                :: (serverId != 2) ->
                    rv_ch[serverId].ch[2]!rv
                fi
            }
    :: // become leader
        (state[serverId] == candidate && (votesGranted[0] + votesGranted[1] + votesGranted[2] > 1)) ->
            state[serverId] = leader;
    :: // handle RequestVote
        (rv_ch[0].ch[serverId]?[rv] || rv_ch[1].ch[serverId]?[rv] || rv_ch[2].ch[serverId]?[rv]) ->
            atomic {
                // calculate the id of the sender
                if
                :: rv_ch[0].ch[serverId]?rv -> i = 0
                :: rv_ch[1].ch[serverId]?rv -> i = 1
                :: rv_ch[2].ch[serverId]?rv -> i = 2
                fi
                assert(i != serverId);
                // update terms
                if
                :: (rv.term > currentTerm[serverId]) ->
                    currentTerm[serverId] = rv.term;
                    state[serverId] = follower;
                    votedFor = NIL
                :: (rv.term <= currentTerm[serverId]) ->
                    skip
                fi

                if
                :: (log[serverId].log[0] == 0) ->
                    lastLogTerm = 0;
                    lastLogIndex = 0
                :: (log[serverId].log[0] != 0 && log[serverId].log[1] == 0) ->
                    lastLogTerm = log[serverId].log[0];
                    lastLogIndex = 1
                :: (log[serverId].log[0] != 0 && log[serverId].log[1] != 0) ->
                    lastLogTerm = log[serverId].log[1];
                    lastLogIndex = 2
                fi

                bool logOk = rv.lastLogTerm > lastLogTerm || rv.lastLogTerm == lastLogTerm && rv.lastLogIndex >= lastLogIndex;
                rvr.voteGranted = rv.term == currentTerm[serverId] && logOk && (votedFor == NIL || votedFor == i);

                // rvr.voteGranted = rv.term == currentTerm && (votedFor == NIL || votedFor == i);

                rvr.term = currentTerm[serverId];
                if
                :: rvr.voteGranted -> votedFor = i
                :: !rvr.voteGranted -> skip
                fi
end:            rvr_ch[serverId].ch[i]!rvr
            }
    :: // handle RequestVoteResponse
        (rvr_ch[0].ch[serverId]?[rvr] || rvr_ch[1].ch[serverId]?[rvr] || rvr_ch[2].ch[serverId]?[rvr]) ->
            atomic {
                // calculate the id of the sender
                if
                :: rvr_ch[0].ch[serverId]?rvr -> i = 0
                :: rvr_ch[1].ch[serverId]?rvr -> i = 1
                :: rvr_ch[2].ch[serverId]?rvr -> i = 2
                fi
                assert(i != serverId);

                if
                :: (rvr.term > currentTerm[serverId]) -> // update terms
                    currentTerm[serverId] = rvr.term;
                    state[serverId] = follower;
                    votedFor = NIL
                :: (rvr.term == currentTerm[serverId] && rvr.voteGranted) ->
                    votesGranted[i] = 1
                :: !(rvr.term > currentTerm[serverId]) && !(rvr.term == currentTerm[serverId] && rvr.voteGranted) ->
                    skip
                fi
            }

    :: // append entries
        (state[serverId] == leader) ->
            atomic {
                if
                :: (serverId != 0) -> i = 0
                :: (serverId != 1) -> i = 1
                :: (serverId != 2) -> i = 2
                fi

                ae.term = currentTerm[serverId];
                if
                :: (commitIndex > 0 && log[serverId].log[0] != log[i].log[0]) ->
                    ae.index = 0
                :: (commitIndex > 1 && log[serverId].log[0] == log[i].log[0] && log[serverId].log[1] != log[i].log[1]) ->
                    ae.index = 1
                    ae.prevLogTerm = log[i].log[0]
                :: ae.index = NIL
                fi
end:            ae_ch[serverId].ch[i]!ae
            }
    :: // handle AppendEntry
        (ae_ch[0].ch[serverId]?[ae] || ae_ch[1].ch[serverId]?[ae] || ae_ch[2].ch[serverId]?[ae]) ->
            atomic {
                // calculate the id of the sender
                if
                :: ae_ch[0].ch[serverId]?ae -> i = 0
                :: ae_ch[1].ch[serverId]?ae -> i = 1
                :: ae_ch[2].ch[serverId]?ae -> i = 2
                fi
                assert(i != serverId);

                // update terms
                if
                :: (ae.term > currentTerm[serverId]) ->
                    currentTerm[serverId] = ae.term;
                    state[serverId] = follower;
                    votedFor = NIL
                :: (ae.term <= currentTerm[serverId]) ->
                    skip
                fi
                assert(ae.term <= currentTerm[serverId]);

                // return to follower state
                if
                :: (ae.term == currentTerm[serverId] && state[serverId] == candidate) ->
                    state[serverId] = follower;
                    votedFor = NIL
                :: (ae.term != currentTerm[serverId] || state[serverId] != candidate) ->
                    skip
                fi
                assert(!(ae.term == currentTerm[serverId]) || (state[serverId] == follower));
                
                bool logOk = ae.index == 0 || ae.index == 1 && ae.prevLogTerm == log[i].log[0];
                aer.term = currentTerm[i];
end:            if
                :: (ae.term < currentTerm[i] || ae.term == currentTerm[serverId] && state[serverId] == follower && !logOk) -> // reject request
                    aer.success = 0;
                    aer_ch[serverId].ch[i]!aer
                :: (ae.term == currentTerm[serverId] && state[serverId] == follower && logOk) ->
                    aer.success = 1;

                    log[serverId].log[ae.index] = ae.term;
                    commitIndex = leaderCommit;

                    aer_ch[serverId].ch[i]!aer
                fi
            }
    :: // handle AppendEntryResponse
        (aer_ch[0].ch[serverId]?[aer] || aer_ch[1].ch[serverId]?[aer] || aer_ch[2].ch[serverId]?[aer]) ->
            atomic {
                // calculate the id of the sender
                if
                :: aer_ch[0].ch[serverId]?aer -> i = 0
                :: aer_ch[1].ch[serverId]?aer -> i = 1
                :: aer_ch[2].ch[serverId]?aer -> i = 2
                fi
                assert(i != serverId);

                if
                :: (aer.term > currentTerm[serverId]) -> // update terms
                    currentTerm[serverId] = aer.term;
                    state[serverId] = follower;
                    votedFor = NIL
                :: (aer.term < currentTerm[serverId]) ->
                    skip
                :: (aer.term == currentTerm[serverId] && aer.success) ->
                    assert(state[serverId] == leader);
                    assert(leaderCommit == commitIndex);

                    // advance commit index
                    // as we only have 3 servers
                    // one success AppendEntry means committed

                    commitIndex = commitIndex + 1;
                    leaderCommit = leaderCommit + 1
                :: (aer.term == currentTerm[serverId] && !aer.success) ->
                    skip
                fi
            }
    :: // client request
        (state[serverId] == leader && log[serverId].log[1] == 0) ->
            if
            :: log[serverId].log[0] == 0 -> log[serverId].log[0] = currentTerm[serverId]
            :: log[serverId].log[1] == 0 -> log[serverId].log[1] = currentTerm[serverId]
            fi 
    od
};

init {
    run server(0);
    run server(1);
    run server(2)
}

ltl electionSafety {
    always !(
        (state[0] == leader && state[1] == leader && currentTerm[0] == currentTerm[1])
        || (state[0] == leader && state[2] == leader && currentTerm[0] == currentTerm[2])
        || (state[1] == leader && state[2] == leader && currentTerm[1] == currentTerm[2])
    )
}