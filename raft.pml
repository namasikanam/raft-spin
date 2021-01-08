#define MAX_TERM 3 // 1 to 3
#define MAX_LOG 2 // 1 to 2
#define MAX_SERVER // 1 to 3

#define NIL 10 // a number that won't be used

byte commitIndex = 0;

typedef AppendEntry {
    byte term, prevLogIndex, prevLogTerm, entry
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

// The following variables are actually local,
// we move them globally, because SPIN doesn't support
// that represent LTL with local variables.
mtype:State = { leader, candidate, follower };
mtype:State state[3];
byte currentTerm[3];

// TOOD: 这个 provided 可能还得再考虑一下
proctype server(byte serverId) provided (commitIndex < MAX_LOG) {
    state[serverId] = follower;
    byte votedFor = NIL;
    byte log[2]; // note: the index is 1-based
    // byte nextIndex2, nextIndex3;
    // byte matchIndex2, matchIndex3;
    
    // helpers
    bool votesGranted[3];
    RequestVote rv;
    byte lastLogTerm, lastLogIndex;
    RequestVoteResponse rvr;
    byte i;

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
                :: (log[0] == 0) ->
                    rv.lastLogTerm = 0;
                    rv.lastLogIndex = 0
                :: (log[0] != 0 && log[1] == 0) ->
                    rv.lastLogTerm = log[0];
                    rv.lastLogIndex = 1
                :: (log[0] != 0 && log[1] != 0) ->
                    rv.lastLogTerm = log[1];
                    rv.lastLogIndex = 2
                fi

                for (i : 0 .. 2) {
                    if
                    :: (i != serverId) -> rv_ch[serverId].ch[i]!rv
                    :: (i == serverId) -> skip
                    fi
                }
            }
    :: // become leader
        (state[serverId] == candidate && (votesGranted[0] + votesGranted[1] + votesGranted[2] > 1)) ->
            atomic {
                state[serverId] = leader;
                // if
                // :: (log[0] == 0) ->
                //     nextIndex2 = 1
                // :: (log[0] != 0 && log[1] == 0) ->
                //     nextIndex2 = 2
                // :: (log[0] != 0 && log[1] != 0) ->
                //     nextIndex2 = 3
                // fi
                // nextIndex3 = nextIndex2;

                // matchIndex2 = 0;
                // matchIndex3 = 0;
            }
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

                if
                :: (rv.term > currentTerm[serverId]) ->
                    currentTerm[serverId] = rv.term;
                    state[serverId] = follower;
                    votedFor = NIL
                :: (rv.term <= currentTerm[serverId]) ->
                    skip
                fi

                if
                :: (log[0] == 0) ->
                    lastLogTerm = 0;
                    lastLogIndex = 0
                :: (log[0] != 0 && log[1] == 0) ->
                    lastLogTerm = log[0];
                    lastLogIndex = 1
                :: (log[0] != 0 && log[1] != 0) ->
                    lastLogTerm = log[1];
                    lastLogIndex = 2
                fi

                bool logOk = rv.lastLogTerm > lastLogTerm || rv.lastLogTerm == lastLogTerm && rv.lastLogIndex >= lastLogIndex;
                rvr.voteGranted = rv.term == currentTerm[serverId] && logOk && (votedFor == 0 || votedFor == 1);

                // rvr.voteGranted = rv.term == currentTerm && (votedFor == NIL || votedFor == i);

                rvr.term = currentTerm[serverId];
                if
                :: rvr.voteGranted -> votedFor = i
                :: !rvr.voteGranted -> skip
                fi
                rvr_ch[serverId].ch[i]!rvr
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
                :: (rvr.term > currentTerm[serverId]) ->
                    currentTerm[serverId] = rvr.term;
                    state[serverId] = follower;
                    votedFor = NIL
                :: (rvr.term == currentTerm[serverId] && rvr.voteGranted) ->
                    votesGranted[i] = 1
                :: !(rvr.term > currentTerm[serverId]) && !(rvr.term == currentTerm[serverId] && rvr.voteGranted) ->
                    skip
                fi
            }
    // TODO :: // append entry
    // TODO :: // handle AppendEntry
    // TODO :: // handle AppendEntryResponse
    // TODO :: // client request
    // TODO :: // advance commit index
    od
};

init {
    run server(0);
    run server(1);
    run server(2)
}

// ltl electionSafety {
//     always !(
//         (state[0] == leader && state[1] == leader && currentTerm[0] == currentTerm[1])
//         || (state[0] == leader && state[2] == leader && currentTerm[0] == currentTerm[2])
//         || (state[1] == leader && state[2] == leader && currentTerm[1] == currentTerm[2])
//     )
// }