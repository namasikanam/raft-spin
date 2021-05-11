## Formally verified Raft in SPIN

This is a formally verified Raft specification in SPIN, as a course project of *Software Formal Verification*, 2020 Autumn, Tsinghua University.

This main references of this work are [the Raft paper](https://raft.github.io/raft.pdf), [PhD dissertation of Diego Ongaro](https://github.com/ongardie/dissertation) and [TLA+ formal model of Raft](https://github.com/ongardie/raft.tla).

[Here](./report.md) is the technial report (in Chinese).

### Requirements

- Model checker: SPIN (~6.5.1)

A large memory space is needed to run.

For Linux, it's recommended to unlimit the memory of process by the following way:
```bash
ulimit -s unlimited
```

### Verification

As it takes a long time to verify all properties together, it's better to verify each property separately.

The following command is recommended:
```bash
$ spin -run -a -bit -bcs -n [-noclaim | -ltl p] raft.pml
```

The interpretation of the used parameters:
- `-run`: model check rather than simulate.
- `-a`: inspect acceptance cycles, which is needed for verifying LTL properties.
- `-bit`: store states by bit, to save space cost.
- `-bcs`: use bounded-context-switching algorithm to speed up.
- `-n`: close the output of unreachable states. Because we verify each property seperately, other unverified properties will generate many unreachable states. Thus, we need to close the output of these many unreachable states.

The followings are the verification commands for all 6 properties in the Raft paper. The total time to run all commands is about 1 hour.

Deadlock (invalid end state)
```bash
$ spin -run -a -bit -bcs -n -noclaim raft.pml
```

Election Safety
```bash
$ spin -run -a -bit -bcs -n -ltl electionSafety raft.pml
```

Leader Append-Only (As this property is too complicated, we decompose it into 6 sub-properties. The valid of original property is equivalent to the valid of all 6 sub-properties.)
```
$ spin -run -a -bit -bcs -n -ltl leaderAppendOnly00 raft.pml
$ spin -run -a -bit -bcs -n -ltl leaderAppendOnly01 raft.pml
$ spin -run -a -bit -bcs -n -ltl leaderAppendOnly10 raft.pml
$ spin -run -a -bit -bcs -n -ltl leaderAppendOnly11 raft.pml
$ spin -run -a -bit -bcs -n -ltl leaderAppendOnly20 raft.pml
$ spin -run -a -bit -bcs -n -ltl leaderAppendOnly21 raft.pml
```

Log Matching
```
$ spin -run -a -bit -bcs -n -ltl electionSafety raft.pml
```

Leader Completeness
```
$ spin -run -a -bit -bcs -n -ltl electionSafety raft.pml
```

State Machine Safety
```
$ spin -run -a -bit -bcs -n -ltl electionSafety raft.pml
```

