# 使用 SPIN 对 Raft 算法的建模与验证

> 计 72 谢兴宇

## 问题描述

Paxos 共识算法以难以理解著称，为了简化 Paxos 的实现和理解难度，Diego Ongaro 等人于 ATC'14 提出了 Raft 算法。

共识算法在可靠大规模软件系统中处于关键地位，它用于保障集群整体在一些成员出故障时依然能够正常工作。在 replicated state machine 的语境下，共识算法就是要保障各机器的 replicated log 一致。实际系统中的共识算法通常有下列性质：
- 在 non-Byzantine conditions 下（比如网络延迟、丢包、消息重复、消息序列重排）保障 safety （不会返回错误的结果）。
- 只要保证每一时刻大多数的 server 都可工作，整个集群就是可工作的。任一个 server 可能突然宕机，或者是重新加入集群，不过要假设其存储是稳定的。
- 一致性不依赖于时间（比如错误的时钟和极慢的消息传递）。
- 小部分特别慢的 server 不会影响集群的整体性能。

Raft 使用一种基于 leader 的方式来实现共识算法：首先选出一个 leader，然后由这个 leader 来管理 replicated log，leader 接受来自客户端的服务请求，然后将其复制给其他的 server，并告诉他们何时可以执行这个请求。当 leader 宕机或失联时，集群中会再选出一个新的 leader。

虽然 Raft 极大地简化了 Paxos，但其中事实上也有相当繁多的细节，这里就不赘述了。

## 相关工作

Diego Ongaro 在其博士论文中讨论了验证 Raft 的几种路径，在早期他们尝试过 Murphi model checker、之后试过 TLA model checker 和 TLA proof system，可 model checking 面对的状态空间增长过快，无法在有足够信服力的参数上验证，theorem proving 过于乏味及耗时。最终他们的做法是，使用 TLA+ 给出一个正确的 formal model，在其基础上再做安全属性的 paper proof。（[Ph.D. dissertation](https://github.com/ongardie/dissertation#readme)）

Raft 另一个值得一提的 formal model 是由 Inria 完成的，其使用 LNT 来描述，其后端虽然有验证工具箱 CADP，但这个工作并没有做验证，而是从模型中自动化生成代码。（[paper](https://hal.inria.fr/hal-01086522)）

对 Raft 的第一个（似乎也是至今唯一一个）比较完整的形式化验证工作是由华盛顿大学完成的，基于分布式系统形式化验证框架 [Verdi](http://verdi.uwplse.org/)，Verdi 是基于定理证明器 Coq 开发而来。该工作证明了 Raft 的原始论文指出的五条安全属性中的三条。（[paper](http://verdi.uwplse.org/raft-proof.pdf)）

## 工具选取

我选择了使用 Promela 来描述模型，使用 SPIN 来做模型检测，主要是出于如下考量：
- 相较之 NuSMV，SPIN 对分布式系统和协议的描述有更好的支持，比如异步性、消息传递等；
- 相较之 TLA+，SPIN 简单的类型系统可以更方便地缩小状态空间；
- 相较之 CADP，SPIN 有更全的文档和更大的社区，而且面向 model checking 有更好的优化。

## 建模思路

对 Raft 的建模主要参考了 Raft 的[原始论文](https://raft.github.io/raft.pdf)、Diego Ongaro 的 [PhD dissertation](https://github.com/ongardie/dissertation#readme) 和 [TLA+ 版本的 formal model](https://github.com/ongardie/raft.tla)。

### 变迁

从最宏观的角度来看，每一个 server 的状态机有下面几个 transition：
- timeout 并且发起新一轮投票
- restart，状态回归 follower，但所存储的量是稳定的
- request vote
- become leader
- handle RequestVote
- handle RequestVoteResponse
- append entry
- handle AppendEntry
- handle AppendEntryResponse
- client request

为了简化状态空间，以上每一个 transition 内部都是 atomic 的。

### 参数

为了简化状态空间，我们需要取尽量小的模型参数。我的取值是：
- `MAX_TERM 3`
- `MAX_LOG 2`
- `MAX_SERVER 3`

这是可以反映设计意图的最小参数，`MAX_SERVER` 和 `MAX_LOG` 的最小性是显然的，`MAX_TERM` 的最小性可以从下面的两张图中直观地看出。

这里我们直观地解释一下，为什么在这个参数配置下，Raft 的核心设计意图依然能够得以体现：
- 一方面，在最终的模型里，经过 SPIN 的检验，除了几个被设计为不可达的程序点（比如 `end`），每一个程序点都是可达的。
- 另一方面，[Raft 的论文](https://raft.github.io/raft.pdf) 中的两张关键的解释设计意图的图（Figure 7 和 Figure 8）都可以在该参数配置下复现。

![](img/figure7.png)

上图复现了 Figure 7，表明 follower 的 log 相对于 leader 的 log 可能出现的各种情况。用于说明一个 follower 可能会没有该有的 entry（a），也可能会有额外的 uncommitted entry（b），也可能既缺了该有的 entry 又有额外的 uncommitted entry（c）。举例而言，场景 (c) 可能是这样的，这个 server 在 term 1 是 leader，这时它收到了一个 client request，并将其放到了自己的 log 里，但在它来得及向其他 server 发送 AppendEntries 请求之前，就宕机了，直到 term 4 才重新连入集群。

![](img/figure8.png)

上图复现了 Figure 8，以说明为何 leader 要被设计成不能用旧的 term 的 log entry 来确定 commitment。在 (a) 中，S1 是 leader。在 (b) 中，S1 宕机，S3 被 S2 和 S3 投票选为 term 2 的 leader。在 (c) 中，S3 宕机，S1 重连并被 S1 和 S2 选为 leader，于是 S1 将 term 1 的 entry 复制给 S2，并收到了一个新的 entry。这时 term 1 的 entry 虽然已经被复制到了大多数 server 中，但它并不能被 commit。这样，下面可能有两种情况发生，并且它们都是合法的。如果 (d1) 发生了，即 S1 宕机了，S3 由 S2 和 S3 投票当选为 leader，并用自己 term 2 的 entry 重写其他 server 在 index 1 的 log。如果 (d2) 发生了，即 S1 没有宕机，继续作为 leader，把自己在 term 3 收到的 entry 复制给 S2，这样 term 3 的 entry 就会被 commit，并且之前 term 1 的 entry 也会被 commit。

以上两图是 Raft 的设计中最为关键和精巧的两个部分，从以上两图中也可比较直观地看出 `MAX_TERM` 的最小值应为 3。

### 简化

为了便于验证，模型中有大量细节上的简化和假设，至少有以下几点（对于关键参数和变量的命名来自[原始论文]([原始论文](https://raft.github.io/raft.pdf))的 Figure 2）：
- 由于 SPIN 不支持对于局部变量的性质的验证，我们将每个 server 的状态（follower、candidate 或者 leader）、当前见到的最新的 term（`currentTerm`）、log 和已知的最大的被 commit 的 index（`commitIndex`）均设为了全局变量。利用这一便利，我们省去了 `nextIndex` 和 `matchIndex`，在发送 `AppendEntries` 时 leader 直接读取对应 server 的 log，来求出应该要写入的 index。
- 为了避免无限 split vote，原始论文中使用了比较精巧的 randomized timeout 的设计。但在我们的模型中，由于没有“绝对时间”的概念，必须要放弃 timeout 的随机性。所以对于本模型而言，假如没有最大的 term 的限制，确实是有可能出现无限 split vote 的情况的。
- 为了刻画消息传递，我们使用了 SPIN 的 message channel，每一对 server 的每一种 request/response 均有一个 channel。我们使用的 channel 相比于理想状态下的 channel，会有一个特征是，如果 channel 里面已有消息，再发消息的时候会拥塞。
- 从模型角度来看，`lastApplied` 只是一个单调递增并且不超过 `commitIndex` 的量，只是徒增状态复杂度，不是很有意义，这里我们将其省略。
- 作为 AppendEntries 的参数的 entry 至多有 1 个，因为不断地重写/添加 1 个 entry，和一次性重写/添加多个 entry 是等价的。
- client request 会直接给 leader，而不会经由其他 server 转发，这样我们也可省略 `leaderId`。
- entry 的 command 对于模型的抽象性质没有影响，我们将其省略，对于每个 entry 只保留其 term 即可。

## 安全属性

我们验证的是死锁和来自 Raft 的 paper 中五条关键的安全属性，这里我们将其在简化后的模型中重新描述出来。方便在报告中简要地描述，我在 LTL 公式中引入了一些符号，但它们都非常容易理解，并且也可以很容易地被还原为普通的 LTL 公式。

### 死锁

我们将且仅将以下两种状态设为合法的结束状态：
- 当前 server 在 timeout 之后导致其 term 超过了 `MAX_TERM`
- 当前 server 的 `commitIndex`（已知的自己的 log 中被 commit 的 entry 的最大编号）达到了 `MAX_LOG`
- 在发送消息时 channel 拥塞

### Election Safety

每个 term 至多会选出一个 leader。

$$G \neg \bigvee_{i \not= j} (\mathrm{state}_i = \mathrm{state}_j \land \mathrm{state}_i = \mathrm{state}_j \land \mathrm{currentTerm}_i = \mathrm{currentTerm}_j)$$

其中，$i, j$ 为 server 的编号。

### Leader Append-Only

leader 不会重写或删掉它的 log 中的 entry，它只会加入新的 entry。

$G \bigwedge_{i, j} (\mathrm{state}_i = \mathrm{leader} \land j < \mathrm{len(log}_i\mathrm{)} \to \bigvee_{k} ((\mathrm{log}_i[j] = k) W (\mathrm{state}_i \not= \mathrm{leader})))$

其中，$i$ 为 server 的编号，$j$ 为 log index，$k$ 为 term。

由于这个 LTL 公式太过复杂，为了便于验证，我们将其拆分成等价的 `MAX_TERM * MAX_LOG = 6` 个公式独立验证。拆分方式是交换前两个符号的顺序，得到

$\bigwedge_{i, j} G (\mathrm{state}_i = \mathrm{leader} \land j < \mathrm{len(log}_i\mathrm{)} \to \bigvee_{k} ((\mathrm{log}_i[j] = k) W (\mathrm{state}_i \not= \mathrm{leader})))$

再将第一个 $\wedge$ 打开即可。

### Log Matching

如果两个 log 包含有属于同一个 term 的 entry，那么这两个 log 直到这个 entry 处都是相等的。

$$G \bigwedge_{i \not= j} (2 = \mathrm{len(log}_i \mathrm{)} \land 2 = \mathrm{len(log}_i \mathrm{)} \land \mathrm{log}_i[2] = \mathrm{log}_j[2] \to \mathrm{log}_i[1] = \mathrm{log}_j[1])$$

其中，$i, j$ 为 server 的编号。

### Leader Completeness

如果一个 log entry 在一个 term 被 commit 了，那么这个 entry 会出现在之后所有 leader 的 log 中。

对这条安全属性的刻画不那么显然，需要再佐以这样一个观察：在没有最大 term 限制的情况下，所有的 server 将来都是有可能成为 leader 的。基于这个观察，上述安全属性，可以等价地表述为下面的 LTL 公式。

$$G \bigwedge_{i} (\mathrm{commitIndex}[i] = 1 \to G \bigwedge_{j \not= i} (\mathrm{state}_j = \mathrm{leader} \to \mathrm{log}_i[1] = \mathrm{log}_j[1]) )$$

其中，$i, j$ 为 server 的编号。

### State Machine Safety

如果一个 server 认为一个 entry 已经被 commit 了，那么在同样的 index 上，不会有其他的 server 认为一个不同的 entry 被 commit 了。

$$G \bigwedge_{i \not= j} (\mathrm{commitIndex}[i] = 1 \land \mathrm{commitIndex}[j] = 1 \to \mathrm{log}_i[1] = \mathrm{log}_j[1])$$

其中，$i, j$ 为 server 的编号。

## 总结与反思

这次实验让我体验到了如何将模型检测应用在一个真正的分布式协议上，也在反复简化和调试模型的过程中体会到了现有验证技术的局限。

如何针对特殊的或新的场景，设计特设性的验证算法，或许是一件值得考虑的事。

并且，当模型如此复杂，拥有如此多的细节时，如何说明所建模型没有过度简化、而是很好地保留了原本的设计意图，似乎也是一件值得考虑的事。

另外，在学习用 TLA+ 描述的 formal model 时，我发现其对 commitIndex 的处理似乎有一个 bug。其将 AppendEntries 简化为了至多只能带一个 entry，然而这也就意味着当处理 AppendEntries 请求时，如果 leaderCommit > commitIndex + 1，是不能将 leaderCommit 直接赋给 commitIndex 的。

## 附录：运行结果

为方便阅览，对输出中反复的部分有所省略。

### 死锁

```bash
$ ./spin651_linux64 -run -a -bit -bcs -n -noclaim raft.pml
ltl electionSafety: [] (! ((((((state[0]==3)) && ((state[1]==3))) && ((currentTerm[0]==currentTerm[1]))) || ((((state[0]==3)) && ((state[2]==3))) && ((currentTerm[0]==currentTerm[2])))) || ((((state[1]==3)) && ((state[2]==3))) && ((currentTerm[1]==currentTerm[2])))))
...........................
ltl stateMachineSafety: [] ((((! (((commitIndex[0]==1)) && ((commitIndex[1]==1)))) || ((log[0].log[0]==log[1].log[0]))) && ((! (((commitIndex[0]==1)) && ((commitIndex[2]==1)))) || ((log[0].log[0]==log[2].log[0])))) && ((! (((commitIndex[1]==1)) && ((commitIndex[2]==1)))) || ((log[1].log[0]==log[2].log[0]))))
  the model contains 10 never claims: stateMachineSafety, leaderCompleteness, logMatching, leaderAppendOnly21, leaderAppendOnly20, leaderAppendOnly11, leaderAppendOnly10, leaderAppendOnly01, leaderAppendOnly00, electionSafety
  only one claim is used in a verification run
  choose which one with ./pan -a -N name (defaults to -N electionSafety)
  or use e.g.: spin -search -ltl electionSafety raft.pml
Depth=     375 States=    1e+06 Transitions= 1.37e+06 Memory=    19.345 t=      2.8 R=   4e+05
Depth=     554 States=    2e+06 Transitions= 2.76e+06 Memory=    19.345 t=     4.78 R=   4e+05
..............................
Depth=    9999 States=  4.1e+07 Transitions= 6.29e+07 Memory=    21.005 t=     90.1 R=   5e+05
Depth=    9999 States=  4.2e+07 Transitions= 6.49e+07 Memory=    21.005 t=     92.7 R=   5e+05

(Spin Version 6.5.1 -- 20 December 2019)
        + Partial Order Reduction
        + Scheduling Restriction (-L0)

Bit statespace search for:
        never claim             - (not selected)
        assertion violations    +
        acceptance   cycles     + (fairness disabled)
        invalid end states      +

State-vector 452 byte, depth reached 9999, errors: 0
 42913834 states, stored
 23813228 states, matched
 66727062 transitions (= stored+matched)
1.5639451e+08 atomic steps

hash factor: 3.12761 (best if > 100.)

bits set per state: 3 (-k3)

Stats on memory usage (in Megabytes):
19644.394       equivalent memory usage for states (stored*(State-vector + overhead))
   16.000       memory used for hash array (-w27)
    0.076       memory used for bit stack
    0.611       memory used for DFS stack (-m10000)
    4.279       other (proc and chan stacks)
   21.005       total actual memory usage



pan: elapsed time 94.9 seconds
pan: rate 452010.05 states/second
```

### Election Safety

```bash
$ ./spin651_linux64 -run -a -bit -bcs -n -ltl electionSafety raft.pml
ltl electionSafety: [] (! ((((((state[0]==3)) && ((state[1]==3))) && ((currentTerm[0]==currentTerm[1]))) || ((((state[0]==3)) && ((state[2]==3))) && ((currentTerm[0]==currentTerm[2])))) || ((((state[1]==3)) && ((state[2]==3))) && ((currentTerm[1]==currentTerm[2])))))
.........................
ltl stateMachineSafety: [] ((((! (((commitIndex[0]==1)) && ((commitIndex[1]==1)))) || ((log[0].log[0]==log[1].log[0]))) && ((! (((commitIndex[0]==1)) && ((commitIndex[2]==1)))) || ((log[0].log[0]==log[2].log[0])))) && ((! (((commitIndex[1]==1)) && ((commitIndex[2]==1)))) || ((log[1].log[0]==log[2].log[0]))))
  the model contains 10 never claims: stateMachineSafety, leaderCompleteness, logMatching, leaderAppendOnly21, leaderAppendOnly20, leaderAppendOnly11, leaderAppendOnly10, leaderAppendOnly01, leaderAppendOnly00, electionSafety
  only one claim is used in a verification run
  choose which one with ./pan -a -N name (defaults to -N electionSafety)
  or use e.g.: spin -search -ltl electionSafety raft.pml
pan: ltl formula electionSafety
Depth=     529 States=    1e+06 Transitions= 1.37e+06 Memory=    19.345 t=     5.12 R=   2e+05
Depth=     770 States=    2e+06 Transitions= 2.76e+06 Memory=    19.345 t=     7.62 R=   3e+05
.........................
Depth=    9999 States=  4.4e+07 Transitions= 7.03e+07 Memory=    20.614 t=      133 R=   3e+05
Depth=    9999 States=  4.5e+07 Transitions= 7.23e+07 Memory=    20.614 t=      137 R=   3e+05

(Spin Version 6.5.1 -- 20 December 2019)
        + Partial Order Reduction
        + Scheduling Restriction (-L0)

Bit statespace search for:
        never claim             + (electionSafety)
        assertion violations    + (if within scope of claim)
        acceptance   cycles     + (fairness disabled)
        invalid end states      - (disabled by never claim)

State-vector 468 byte, depth reached 9999, errors: 0
 45782122 states, stored
 28055486 states, matched
 73837608 transitions (= stored+matched)
1.7517181e+08 atomic steps

hash factor: 2.93166 (best if > 100.)

bits set per state: 3 (-k3)

Stats on memory usage (in Megabytes):
21655.972       equivalent memory usage for states (stored*(State-vector + overhead))
   16.000       memory used for hash array (-w27)
    0.076       memory used for bit stack
    0.611       memory used for DFS stack (-m10000)
    3.888       other (proc and chan stacks)
   20.614       total actual memory usage



pan: elapsed time 139 seconds
pan: rate 328540.52 states/second
```

### Leader Append-Only

```bash
$ ./spin651_linux64 -run -a -bit -bcs -n -ltl leaderAppendOnly00 raft.pml
ltl electionSafety: [] (! ((((((state[0]==3)) && ((state[1]==3))) && ((currentTerm[0]==currentTerm[1]))) || ((((state[0]==3)) && ((state[2]==3))) && ((currentTerm[0]==currentTerm[2])))) || ((((state[1]==3)) && ((state[2]==3))) && ((currentTerm[1]==currentTerm[2])))))
.....................................
ltl stateMachineSafety: [] ((((! (((commitIndex[0]==1)) && ((commitIndex[1]==1)))) || ((log[0].log[0]==log[1].log[0]))) && ((! (((commitIndex[0]==1)) && ((commitIndex[2]==1)))) || ((log[0].log[0]==log[2].log[0])))) && ((! (((commitIndex[1]==1)) && ((commitIndex[2]==1)))) || ((log[1].log[0]==log[2].log[0]))))
  the model contains 10 never claims: stateMachineSafety, leaderCompleteness, logMatching, leaderAppendOnly21, leaderAppendOnly20, leaderAppendOnly11, leaderAppendOnly10, leaderAppendOnly01, leaderAppendOnly00, electionSafety
  only one claim is used in a verification run
  choose which one with ./pan -a -N name (defaults to -N electionSafety)
  or use e.g.: spin -search -ltl electionSafety raft.pml
pan: ltl formula leaderAppendOnly00
Depth=     483 States=    1e+06 Transitions=    4e+06 Memory=    19.345 t=     6.64 R=   2e+05
Depth=     529 States=    2e+06 Transitions= 8.05e+06 Memory=    19.345 t=     12.7 R=   2e+05
....................................
Depth=    9999 States=  4.5e+07 Transitions= 1.49e+08 Memory=    20.614 t=      254 R=   2e+05
Depth=    9999 States=  4.6e+07 Transitions= 1.51e+08 Memory=    20.614 t=      257 R=   2e+05

(Spin Version 6.5.1 -- 20 December 2019)
        + Partial Order Reduction
        + Scheduling Restriction (-L0)

Bit statespace search for:
        never claim             + (leaderAppendOnly00)
        assertion violations    + (if within scope of claim)
        acceptance   cycles     + (fairness disabled)
        invalid end states      - (disabled by never claim)

State-vector 468 byte, depth reached 9999, errors: 0
 46759169 states, stored
1.0550942e+08 states, matched
1.5226859e+08 transitions (= stored+matched)
3.4994183e+08 atomic steps

hash factor: 2.8704 (best if > 100.)

bits set per state: 3 (-k3)

Stats on memory usage (in Megabytes):
22118.137       equivalent memory usage for states (stored*(State-vector + overhead))
   16.000       memory used for hash array (-w27)
    0.076       memory used for bit stack
    0.611       memory used for DFS stack (-m10000)
    3.887       other (proc and chan stacks)
   20.614       total actual memory usage



pan: elapsed time 260 seconds
pan: rate 179842.96 states/second

$ ./spin651_linux64 -run -a -bit -bcs -n -ltl leaderAppendOnly01 raft.pml
ltl electionSafety: [] (! ((((((state[0]==3)) && ((state[1]==3))) && ((currentTerm[0]==currentTerm[1]))) || ((((state[0]==3)) && ((state[2]==3))) && ((currentTerm[0]==currentTerm[2])))) || ((((state[1]==3)) && ((state[2]==3))) && ((currentTerm[1]==currentTerm[2])))))
..........................
ltl stateMachineSafety: [] ((((! (((commitIndex[0]==1)) && ((commitIndex[1]==1)))) || ((log[0].log[0]==log[1].log[0]))) && ((! (((commitIndex[0]==1)) && ((commitIndex[2]==1)))) || ((log[0].log[0]==log[2].log[0])))) && ((! (((commitIndex[1]==1)) && ((commitIndex[2]==1)))) || ((log[1].log[0]==log[2].log[0]))))
  the model contains 10 never claims: stateMachineSafety, leaderCompleteness, logMatching, leaderAppendOnly21, leaderAppendOnly20, leaderAppendOnly11, leaderAppendOnly10, leaderAppendOnly01, leaderAppendOnly00, electionSafety
  only one claim is used in a verification run
  choose which one with ./pan -a -N name (defaults to -N electionSafety)
  or use e.g.: spin -search -ltl electionSafety raft.pml
pan: ltl formula leaderAppendOnly01
Depth=     529 States=    1e+06 Transitions= 3.02e+06 Memory=    19.345 t=     5.14 R=   2e+05
Depth=     554 States=    2e+06 Transitions= 5.91e+06 Memory=    19.345 t=      9.8 R=   2e+05
..........................
Depth=    9999 States=  4.5e+07 Transitions= 1.28e+08 Memory=    20.614 t=      211 R=   2e+05
Depth=    9999 States=  4.6e+07 Transitions= 1.33e+08 Memory=    20.614 t=      218 R=   2e+05

(Spin Version 6.5.1 -- 20 December 2019)
        + Partial Order Reduction
        + Scheduling Restriction (-L0)

Bit statespace search for:
        never claim             + (leaderAppendOnly01)
        assertion violations    + (if within scope of claim)
        acceptance   cycles     + (fairness disabled)
        invalid end states      - (disabled by never claim)

State-vector 468 byte, depth reached 9999, errors: 0
 46139859 states, stored
 87984155 states, matched
1.3412401e+08 transitions (= stored+matched)
3.6617324e+08 atomic steps

hash factor: 2.90893 (best if > 100.)

bits set per state: 3 (-k3)

Stats on memory usage (in Megabytes):
21825.190       equivalent memory usage for states (stored*(State-vector + overhead))
   16.000       memory used for hash array (-w27)
    0.076       memory used for bit stack
    0.611       memory used for DFS stack (-m10000)
    3.887       other (proc and chan stacks)
   20.614       total actual memory usage



pan: elapsed time 218 seconds
pan: rate 211185.73 states/second

$ ./spin651_linux64 -run -a -bit -bcs -n -ltl leaderAppendOnly10 raft.pml
ltl electionSafety: [] (! ((((((state[0]==3)) && ((state[1]==3))) && ((currentTerm[0]==currentTerm[1]))) || ((((state[0]==3)) && ((state[2]==3))) && ((currentTerm[0]==currentTerm[2])))) || ((((state[1]==3)) && ((state[2]==3))) && ((currentTerm[1]==currentTerm[2])))))
..............................
ltl stateMachineSafety: [] ((((! (((commitIndex[0]==1)) && ((commitIndex[1]==1)))) || ((log[0].log[0]==log[1].log[0]))) && ((! (((commitIndex[0]==1)) && ((commitIndex[2]==1)))) || ((log[0].log[0]==log[2].log[0])))) && ((! (((commitIndex[1]==1)) && ((commitIndex[2]==1)))) || ((log[1].log[0]==log[2].log[0]))))
  the model contains 10 never claims: stateMachineSafety, leaderCompleteness, logMatching, leaderAppendOnly21, leaderAppendOnly20, leaderAppendOnly11, leaderAppendOnly10, leaderAppendOnly01, leaderAppendOnly00, electionSafety
  only one claim is used in a verification run
  choose which one with ./pan -a -N name (defaults to -N electionSafety)
  or use e.g.: spin -search -ltl electionSafety raft.pml
pan: ltl formula leaderAppendOnly10
Depth=     483 States=    1e+06 Transitions= 4.11e+06 Memory=    19.345 t=     5.92 R=   2e+05
Depth=     529 States=    2e+06 Transitions= 8.04e+06 Memory=    19.345 t=     11.2 R=   2e+05
...............................
Depth=    9999 States=  4.6e+07 Transitions= 1.72e+08 Memory=    20.614 t=      259 R=   2e+05
Depth=    9999 States=  4.7e+07 Transitions= 1.74e+08 Memory=    20.614 t=      264 R=   2e+05

(Spin Version 6.5.1 -- 20 December 2019)
        + Partial Order Reduction
        + Scheduling Restriction (-L0)

Bit statespace search for:
        never claim             + (leaderAppendOnly10)
        assertion violations    + (if within scope of claim)
        acceptance   cycles     + (fairness disabled)
        invalid end states      - (disabled by never claim)

State-vector 468 byte, depth reached 9999, errors: 0
 47169656 states, stored
1.2687799e+08 states, matched
1.7404765e+08 transitions (= stored+matched)
4.3060137e+08 atomic steps

hash factor: 2.84543 (best if > 100.)

bits set per state: 3 (-k3)

Stats on memory usage (in Megabytes):
22312.307       equivalent memory usage for states (stored*(State-vector + overhead))
   16.000       memory used for hash array (-w27)
    0.076       memory used for bit stack
    0.611       memory used for DFS stack (-m10000)
    3.888       other (proc and chan stacks)
   20.614       total actual memory usage



pan: elapsed time 265 seconds
pan: rate 178160.05 states/second

$ ./spin651_linux64 -run -a -bit -bcs -n -ltl leaderAppendOnly11 raft.pml
ltl electionSafety: [] (! ((((((state[0]==3)) && ((state[1]==3))) && ((currentTerm[0]==currentTerm[1]))) || ((((state[0]==3)) && ((state[2]==3))) && ((currentTerm[0]==currentTerm[2])))) || ((((state[1]==3)) && ((state[2]==3))) && ((currentTerm[1]==currentTerm[2])))))
...........................
ltl stateMachineSafety: [] ((((! (((commitIndex[0]==1)) && ((commitIndex[1]==1)))) || ((log[0].log[0]==log[1].log[0]))) && ((! (((commitIndex[0]==1)) && ((commitIndex[2]==1)))) || ((log[0].log[0]==log[2].log[0])))) && ((! (((commitIndex[1]==1)) && ((commitIndex[2]==1)))) || ((log[1].log[0]==log[2].log[0]))))
  the model contains 10 never claims: stateMachineSafety, leaderCompleteness, logMatching, leaderAppendOnly21, leaderAppendOnly20, leaderAppendOnly11, leaderAppendOnly10, leaderAppendOnly01, leaderAppendOnly00, electionSafety
  only one claim is used in a verification run
  choose which one with ./pan -a -N name (defaults to -N electionSafety)
  or use e.g.: spin -search -ltl electionSafety raft.pml
pan: ltl formula leaderAppendOnly11
Depth=     529 States=    1e+06 Transitions= 2.84e+06 Memory=    19.345 t=     5.61 R=   2e+05
Depth=     554 States=    2e+06 Transitions= 5.35e+06 Memory=    19.345 t=     9.77 R=   2e+05
.........................
Depth=    9999 States=  5.8e+07 Transitions= 1.52e+08 Memory=    20.614 t=      273 R=   2e+05
Depth=    9999 States=  5.9e+07 Transitions= 1.55e+08 Memory=    20.614 t=      277 R=   2e+05

(Spin Version 6.5.1 -- 20 December 2019)
        + Partial Order Reduction
        + Scheduling Restriction (-L0)

Bit statespace search for:
        never claim             + (leaderAppendOnly11)
        assertion violations    + (if within scope of claim)
        acceptance   cycles     + (fairness disabled)
        invalid end states      - (disabled by never claim)

State-vector 468 byte, depth reached 9999, errors: 0
 59592683 states, stored
 98108790 states, matched
1.5770147e+08 transitions (= stored+matched)
3.9646382e+08 atomic steps

hash factor: 2.25225 (best if > 100.)

bits set per state: 3 (-k3)

Stats on memory usage (in Megabytes):
28188.678       equivalent memory usage for states (stored*(State-vector + overhead))
   16.000       memory used for hash array (-w27)
    0.076       memory used for bit stack
    0.611       memory used for DFS stack (-m10000)
    3.888       other (proc and chan stacks)
   20.614       total actual memory usage



pan: elapsed time 279 seconds
pan: rate    213227 states/second

$ ./spin651_linux64 -run -a -bit -bcs -n -ltl leaderAppendOnly20 raft.pml
ltl electionSafety: [] (! ((((((state[0]==3)) && ((state[1]==3))) && ((currentTerm[0]==currentTerm[1]))) || ((((state[0]==3)) && ((state[2]==3))) && ((currentTerm[0]==currentTerm[2])))) || ((((state[1]==3)) && ((state[2]==3))) && ((currentTerm[1]==currentTerm[2])))))
........................
ltl stateMachineSafety: [] ((((! (((commitIndex[0]==1)) && ((commitIndex[1]==1)))) || ((log[0].log[0]==log[1].log[0]))) && ((! (((commitIndex[0]==1)) && ((commitIndex[2]==1)))) || ((log[0].log[0]==log[2].log[0])))) && ((! (((commitIndex[1]==1)) && ((commitIndex[2]==1)))) || ((log[1].log[0]==log[2].log[0]))))
  the model contains 10 never claims: stateMachineSafety, leaderCompleteness, logMatching, leaderAppendOnly21, leaderAppendOnly20, leaderAppendOnly11, leaderAppendOnly10, leaderAppendOnly01, leaderAppendOnly00, electionSafety
  only one claim is used in a verification run
  choose which one with ./pan -a -N name (defaults to -N electionSafety)
  or use e.g.: spin -search -ltl electionSafety raft.pml
pan: ltl formula leaderAppendOnly20
Depth=     529 States=    1e+06 Transitions= 1.37e+06 Memory=    19.345 t=     3.11 R=   3e+05
Depth=     770 States=    2e+06 Transitions= 2.76e+06 Memory=    19.345 t=     5.82 R=   3e+05
.........................
Depth=    9999 States=  4.5e+07 Transitions=  1.2e+08 Memory=    20.614 t=      202 R=   2e+05
Depth=    9999 States=  4.6e+07 Transitions= 1.25e+08 Memory=    20.614 t=      210 R=   2e+05

(Spin Version 6.5.1 -- 20 December 2019)
        + Partial Order Reduction
        + Scheduling Restriction (-L0)

Bit statespace search for:
        never claim             + (leaderAppendOnly20)
        assertion violations    + (if within scope of claim)
        acceptance   cycles     + (fairness disabled)
        invalid end states      - (disabled by never claim)

State-vector 468 byte, depth reached 9999, errors: 0
 46631082 states, stored
 81496442 states, matched
1.2812752e+08 transitions (= stored+matched)
2.9818026e+08 atomic steps

hash factor: 2.87829 (best if > 100.)

bits set per state: 3 (-k3)

Stats on memory usage (in Megabytes):
22057.549       equivalent memory usage for states (stored*(State-vector + overhead))
   16.000       memory used for hash array (-w27)
    0.076       memory used for bit stack
    0.611       memory used for DFS stack (-m10000)
    3.887       other (proc and chan stacks)
   20.614       total actual memory usage



pan: elapsed time 214 seconds
pan: rate 218208.15 states/second

$ ./spin651_linux64 -run -a -bit -bcs -n -ltl leaderAppendOnly21 raft.pml
ltl electionSafety: [] (! ((((((state[0]==3)) && ((state[1]==3))) && ((currentTerm[0]==currentTerm[1]))) || ((((state[0]==3)) && ((state[2]==3))) && ((currentTerm[0]==currentTerm[2])))) || ((((state[1]==3)) && ((state[2]==3))) && ((currentTerm[1]==currentTerm[2])))))
..............................
ltl stateMachineSafety: [] ((((! (((commitIndex[0]==1)) && ((commitIndex[1]==1)))) || ((log[0].log[0]==log[1].log[0]))) && ((! (((commitIndex[0]==1)) && ((commitIndex[2]==1)))) || ((log[0].log[0]==log[2].log[0])))) && ((! (((commitIndex[1]==1)) && ((commitIndex[2]==1)))) || ((log[1].log[0]==log[2].log[0]))))
  the model contains 10 never claims: stateMachineSafety, leaderCompleteness, logMatching, leaderAppendOnly21, leaderAppendOnly20, leaderAppendOnly11, leaderAppendOnly10, leaderAppendOnly01, leaderAppendOnly00, electionSafety
  only one claim is used in a verification run
  choose which one with ./pan -a -N name (defaults to -N electionSafety)
  or use e.g.: spin -search -ltl electionSafety raft.pml
pan: ltl formula leaderAppendOnly21
Depth=     529 States=    1e+06 Transitions= 1.37e+06 Memory=    19.345 t=     3.66 R=   3e+05
Depth=     770 States=    2e+06 Transitions= 2.76e+06 Memory=    19.345 t=     6.61 R=   3e+05
..............................
Depth=    9999 States=  4.4e+07 Transitions= 8.72e+07 Memory=    20.614 t=      179 R=   2e+05
Depth=    9999 States=  4.5e+07 Transitions= 9.15e+07 Memory=    20.614 t=      184 R=   2e+05

(Spin Version 6.5.1 -- 20 December 2019)
        + Partial Order Reduction
        + Scheduling Restriction (-L0)

Bit statespace search for:
        never claim             + (leaderAppendOnly21)
        assertion violations    + (if within scope of claim)
        acceptance   cycles     + (fairness disabled)
        invalid end states      - (disabled by never claim)

State-vector 468 byte, depth reached 9999, errors: 0
 45763678 states, stored
 48885765 states, matched
 94649443 transitions (= stored+matched)
2.3520682e+08 atomic steps

hash factor: 2.93284 (best if > 100.)

bits set per state: 3 (-k3)

Stats on memory usage (in Megabytes):
21647.248       equivalent memory usage for states (stored*(State-vector + overhead))
   16.000       memory used for hash array (-w27)
    0.076       memory used for bit stack
    0.611       memory used for DFS stack (-m10000)
    3.887       other (proc and chan stacks)
   20.614       total actual memory usage



pan: elapsed time 189 seconds
pan: rate 241547.97 states/second
```

### Log Matching

```bash
./spin651_linux64 -run -a -bit -bcs -n -ltl logMatching raft.pml
ltl electionSafety: [] (! ((((((state[0]==3)) && ((state[1]==3))) && ((currentTerm[0]==currentTerm[1]))) || ((((state[0]==3)) && ((state[2]==3))) && ((currentTerm[0]==currentTerm[2])))) || ((((state[1]==3)) && ((state[2]==3))) && ((currentTerm[1]==currentTerm[2])))))
.............................
ltl stateMachineSafety: [] ((((! (((commitIndex[0]==1)) && ((commitIndex[1]==1)))) || ((log[0].log[0]==log[1].log[0]))) && ((! (((commitIndex[0]==1)) && ((commitIndex[2]==1)))) || ((log[0].log[0]==log[2].log[0])))) && ((! (((commitIndex[1]==1)) && ((commitIndex[2]==1)))) || ((log[1].log[0]==log[2].log[0]))))
  the model contains 10 never claims: stateMachineSafety, leaderCompleteness, logMatching, leaderAppendOnly21, leaderAppendOnly20, leaderAppendOnly11, leaderAppendOnly10, leaderAppendOnly01, leaderAppendOnly00, electionSafety
  only one claim is used in a verification run
  choose which one with ./pan -a -N name (defaults to -N electionSafety)
  or use e.g.: spin -search -ltl electionSafety raft.pml
pan: ltl formula logMatching
Depth=     529 States=    1e+06 Transitions= 1.37e+06 Memory=    19.345 t=     3.07 R=   3e+05
Depth=     770 States=    2e+06 Transitions= 2.76e+06 Memory=    19.345 t=     5.26 R=   4e+05
............................
Depth=    9999 States=  4.8e+07 Transitions= 7.92e+07 Memory=    20.614 t=      160 R=   3e+05
Depth=    9999 States=  4.9e+07 Transitions= 8.13e+07 Memory=    20.614 t=      163 R=   3e+05

(Spin Version 6.5.1 -- 20 December 2019)
        + Partial Order Reduction
        + Scheduling Restriction (-L0)

Bit statespace search for:
        never claim             + (logMatching)
        assertion violations    + (if within scope of claim)
        acceptance   cycles     + (fairness disabled)
        invalid end states      - (disabled by never claim)

State-vector 468 byte, depth reached 9999, errors: 0
 49880233 states, stored
 33137809 states, matched
 83018042 transitions (= stored+matched)
1.9498585e+08 atomic steps

hash factor: 2.6908 (best if > 100.)

bits set per state: 3 (-k3)

Stats on memory usage (in Megabytes):
23594.471       equivalent memory usage for states (stored*(State-vector + overhead))
   16.000       memory used for hash array (-w27)
    0.076       memory used for bit stack
    0.611       memory used for DFS stack (-m10000)
    3.887       other (proc and chan stacks)
   20.614       total actual memory usage



pan: elapsed time 166 seconds
pan: rate 300863.94 states/second
```

### Leader Completeness

```bash
./spin651_linux64 -run -a -bit -bcs -n -ltl leaderCompleteness raft.pml
ltl electionSafety: [] (! ((((((state[0]==3)) && ((state[1]==3))) && ((currentTerm[0]==currentTerm[1]))) || ((((state[0]==3)) && ((state[2]==3))) && ((currentTerm[0]==currentTerm[2])))) || ((((state[1]==3)) && ((state[2]==3))) && ((currentTerm[1]==currentTerm[2])))))
..........................
ltl stateMachineSafety: [] ((((! (((commitIndex[0]==1)) && ((commitIndex[1]==1)))) || ((log[0].log[0]==log[1].log[0]))) && ((! (((commitIndex[0]==1)) && ((commitIndex[2]==1)))) || ((log[0].log[0]==log[2].log[0])))) && ((! (((commitIndex[1]==1)) && ((commitIndex[2]==1)))) || ((log[1].log[0]==log[2].log[0]))))
  the model contains 10 never claims: stateMachineSafety, leaderCompleteness, logMatching, leaderAppendOnly21, leaderAppendOnly20, leaderAppendOnly11, leaderAppendOnly10, leaderAppendOnly01, leaderAppendOnly00, electionSafety
  only one claim is used in a verification run
  choose which one with ./pan -a -N name (defaults to -N electionSafety)
  or use e.g.: spin -search -ltl electionSafety raft.pml
pan: ltl formula leaderCompleteness
Depth=     529 States=    1e+06 Transitions= 1.37e+06 Memory=    19.345 t=     2.84 R=   4e+05
Depth=     770 States=    2e+06 Transitions= 2.76e+06 Memory=    19.345 t=      5.1 R=   4e+05
..........................
Depth=    9999 States=  4.1e+07 Transitions= 6.48e+07 Memory=    20.614 t=      107 R=   4e+05
Depth=    9999 States=  4.2e+07 Transitions= 6.69e+07 Memory=    20.614 t=      111 R=   4e+05

(Spin Version 6.5.1 -- 20 December 2019)
        + Partial Order Reduction
        + Scheduling Restriction (-L0)

Bit statespace search for:
        never claim             + (leaderCompleteness)
        assertion violations    + (if within scope of claim)
        acceptance   cycles     + (fairness disabled)
        invalid end states      - (disabled by never claim)

State-vector 468 byte, depth reached 9999, errors: 0
 42814885 states, stored
 25594325 states, matched
 68409210 transitions (= stored+matched)
1.6135986e+08 atomic steps

hash factor: 3.13484 (best if > 100.)

bits set per state: 3 (-k3)

Stats on memory usage (in Megabytes):
20252.402       equivalent memory usage for states (stored*(State-vector + overhead))
   16.000       memory used for hash array (-w27)
    0.076       memory used for bit stack
    0.611       memory used for DFS stack (-m10000)
    3.888       other (proc and chan stacks)
   20.614       total actual memory usage



pan: elapsed time 114 seconds
pan: rate 375799.92 states/second
```

### State Machine Safety

```bash
./spin651_linux64 -run -a -bit -bcs -n -ltl stateMachineSafety raft.pml
ltl electionSafety: [] (! ((((((state[0]==3)) && ((state[1]==3))) && ((currentTerm[0]==currentTerm[1]))) || ((((state[0]==3)) && ((state[2]==3))) && ((currentTerm[0]==currentTerm[2])))) || ((((state[1]==3)) && ((state[2]==3))) && ((currentTerm[1]==currentTerm[2])))))
.......................
ltl stateMachineSafety: [] ((((! (((commitIndex[0]==1)) && ((commitIndex[1]==1)))) || ((log[0].log[0]==log[1].log[0]))) && ((! (((commitIndex[0]==1)) && ((commitIndex[2]==1)))) || ((log[0].log[0]==log[2].log[0])))) && ((! (((commitIndex[1]==1)) && ((commitIndex[2]==1)))) || ((log[1].log[0]==log[2].log[0]))))
  the model contains 10 never claims: stateMachineSafety, leaderCompleteness, logMatching, leaderAppendOnly21, leaderAppendOnly20, leaderAppendOnly11, leaderAppendOnly10, leaderAppendOnly01, leaderAppendOnly00, electionSafety
  only one claim is used in a verification run
  choose which one with ./pan -a -N name (defaults to -N electionSafety)
  or use e.g.: spin -search -ltl electionSafety raft.pml
pan: ltl formula stateMachineSafety
Depth=     529 States=    1e+06 Transitions= 1.37e+06 Memory=    19.345 t=     3.41 R=   3e+05
Depth=     770 States=    2e+06 Transitions= 2.76e+06 Memory=    19.345 t=     6.72 R=   3e+05
.....................
Depth=    9999 States=  4.5e+07 Transitions= 7.45e+07 Memory=    20.614 t=      152 R=   3e+05
Depth=    9999 States=  4.6e+07 Transitions= 7.65e+07 Memory=    20.614 t=      155 R=   3e+05

(Spin Version 6.5.1 -- 20 December 2019)
        + Partial Order Reduction
        + Scheduling Restriction (-L0)

Bit statespace search for:
        never claim             + (stateMachineSafety)
        assertion violations    + (if within scope of claim)
        acceptance   cycles     + (fairness disabled)
        invalid end states      - (disabled by never claim)

State-vector 468 byte, depth reached 9999, errors: 0
 46549472 states, stored
 30979285 states, matched
 77528757 transitions (= stored+matched)
1.8046186e+08 atomic steps

hash factor: 2.88334 (best if > 100.)

bits set per state: 3 (-k3)

Stats on memory usage (in Megabytes):
22018.946       equivalent memory usage for states (stored*(State-vector + overhead))
   16.000       memory used for hash array (-w27)
    0.076       memory used for bit stack
    0.611       memory used for DFS stack (-m10000)
    3.887       other (proc and chan stacks)
   20.614       total actual memory usage



pan: elapsed time 156 seconds
pan: rate 297535.78 states/second
```
