## 使用说明

### 环境配置

- 模型检测器：SPIN
  - 开发版本为 6.5.1
  - 可参照[这里](http://spinroot.com/spin/Man/README.html#S2)安装
- 测试环境：Linux (Ubuntu 18.04)

运行时可能会占用较大内存空间，建议扩大或取消进程的内存空间限制。在 Linux 上可以使用以下方式：
```bash
ulimit -s unlimited
```

### 运行方式

由于一起验证所有属性时间过长，我们推荐对每一条属性单独验证。

总得来说，推荐使用以下方式运行：
```bash
$ spin -run -a -bit -bcs -n [-noclaim | -ltl p] raft.pml
```

对所用参数的解释：
- `-run`：直接做 model checking，而不是 simulation；
- `-a`：检查 acceptance cycles，验证 LTL 属性时需要开启；
- `-bit`：按位存储状态，以节省空间；
- `-bcs`：使用 bounded-context-switching 算法，以提高效率；
- `-n`：关闭 unreachable 的状态输出，因为我们会单独对每一个属性单独验证，由其他的属性所生成的状态就是 unreachable 的，会带来大量的输出，所以需要关闭。

下面是对每一条属性的验证指令（全部运行一遍需耗时约 1h）

死锁（invalid end state）
```bash
$ spin -run -a -bit -bcs -n -noclaim raft.pml
```

Election Safety
```bash
$ spin -run -a -bit -bcs -n -ltl electionSafety raft.pml
```

Leader Append-Only（由于该条属性太过复杂，我们将其拆分成了 6 条属性分别验证，原属性成立等价于这 6 条属性都成立）
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

