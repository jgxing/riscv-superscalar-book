# 第 3 章 Tomasulo 配套代码

三个可综合模块 + 一个自测 testbench，对应教材第 3 章三个核心机制。

| 文件 | 作用 | 对应原理 |
|---|---|---|
| `rat.v` | 重命名表：源寄存器查标签、目的寄存器重命名、CDB 写回清表项 | 3.2.2 寄存器重命名；WAW 化解 |
| `reservation_station.v` | 保留站条目：操作数就绪判定 + 监听 CDB 唤醒 | 3.2.1 保留站；3.2.3 广播唤醒 |
| `cdb_arbiter.v` | CDB 仲裁：多个结果竞争一根总线 | 3.5 广播瓶颈 |
| `tb_tomasulo.v` | 自测：唤醒 / WAW / 仲裁三组测试 | 3.4、3.5 |

## 运行（需要 Icarus Verilog）

```bash
iverilog -g2012 -o sim.vvp *.v
vvp sim.vvp
```

预期输出（`ALL TESTS PASSED`，10 个 PASS，0 错误）：

```
==== Chapter 3 Tomasulo core mechanisms ====
-- T1 Reservation station wakeup --
  [PASS] After issue: busy=1, ready=0 (waiting vk)
  [PASS] Broadcast #22 (no match): still ready=0
  [PASS] Broadcast #21 (match): ready=1 and vk=7
-- T2 RAT / WAW --
  [PASS] After two writes to R1: latest tag is #24
  [PASS] Broadcast old tag #21: R1 still #24 (WAW ok)
  [PASS] Broadcast new tag #24: R1 entry cleared
-- T3 CDB arbiter --
  [PASS] Two units request: cdb_valid=1
  [PASS] Fixed priority: unit1 wins grant
  [PASS] Broadcast unit1 tag #22
  [PASS] No request: cdb_valid=0
==== Result: 0 errors ====
ALL TESTS PASSED
```

## 教学要点

- **T1** 演示保留站监听：广播不匹配的标签不动，匹配才锁存数据并置 `ready`——这是 RAW 真相关的保持方式。
- **T2** 演示 WAW 化解：R1 被写两次（#21 然后 #24），旧标签 #21 广播时不会误清登记，只有新标签 #24 广播才清除。
- **T3** 演示广播瓶颈：两个功能部件同时完成，一根 CDB 一拍只放行一个（固定优先）。这就是 2 发射扩展到 N 发射时广播带宽成为瓶颈的原因。

> 说明：这些是**教学简化模型**，为突出原理省略了复位后的 complete 握手、多 CDB、物理寄存器堆等工程细节（香山真实做法见教材 3.8 节）。
