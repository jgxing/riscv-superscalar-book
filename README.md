# RISC-V 多发射乱序处理器设计入门教材

一本面向已有五级整数流水线设计经验的读者，讲清多发射乱序处理器背后原理与方法的教材。以 2 发射简化乱序核为教学主线，用 Digital 电路图形化建模系统连接，用 Verilog 骨架验证关键机制。以香山等开源处理器为思想参照，不复刻工程实现。

## 目录结构

```
.
├── 前言.md                     写作动机、目标读者、方法与章节安排
├── 教材大纲.md                 全书编写定位与详细大纲
├── 参考文献与延伸阅读.md        教材、论文、会议、期刊与检索入口
├── 附录A_Digital使用指南.md
├── 附录B_Verilog模块模板.md
├── 附录C_术语与参数速查.md
├── chapters/                   第 1 至 15 章正文（Markdown）
├── figures/                    62 张可编辑 SVG 插图
└── code/
    ├── digital/                14 个 Digital 电路（.dig，XML 格式）
    └── verilog/                11 组可运行 Verilog 代码与测试台
        ├── 03_tomasulo/
        ├── 04_frontend/
        ├── 05_branch/
        ├── 06_fetch/
        ├── 07_decode/
        ├── 09_rename/
        ├── 10_issue/
        ├── 11_execute/
        ├── 12_lsq/
        ├── 13_rob/
        ├── 14_recovery/
        ├── 15_perf/
        └── appendix_b/
```

## 代码清单与测试状态

每组 Verilog 代码都带测试台，可用 Icarus Verilog 直接仿真。下列测试项均已通过。

| 目录 | 内容 | 测试项 |
|---|---|---|
| `03_tomasulo` | RAT、保留站、CDB 仲裁 | 10 |
| `04_frontend` | 取指目标队列 FTQ | 全部通过 |
| `05_branch` | 2 位饱和计数器与 BTB | 16 |
| `06_fetch` | 指令缓冲队列 | 24 |
| `07_decode` | 译码、融合与 uop 拆分 | 30 |
| `09_rename` | 空闲表、RAT 与重命名 | 27 |
| `10_issue` | 发射队列与按年龄仲裁 | 17 |
| `11_execute` | ALU 与旁路选择 | 18 |
| `12_lsq` | 乱序访存队列与转发 | 20 |
| `13_rob` | 重排序缓冲与精确异常 | 17 |
| `14_recovery` | 检查点恢复与冲刷控制 | 17 |
| `15_perf` | 性能计数器与瓶颈判定 | 21 |
| `appendix_b` | FIFO、CAM、优先编码器、仲裁器、交叉开关 | 28 |

## 运行 Verilog 测试

以第 9 章为例，进入对应目录后编译并仿真：

```bash
cd code/verilog/09_rename
iverilog -g2012 -o sim.vvp *.v
vvp sim.vvp
```

每组目录下的 README.md 说明了该组模块的接口、关键逻辑和调试时遇到过的问题。代码是按正文的渐进讲解逐块搭出来的，与教材正文中的代码片段逐字一致。

## 运行 Digital 电路

`.dig` 文件是 XML 格式，用开源软件 Digital 打开。Digital 的下载地址与元件库、子电路、波形观察等用法见 `附录A_Digital使用指南.md`。每个电路都带真值表或可单步观察的信号，便于对照正文理解。

## 配套工具

- [Digital](https://github.com/hneemann/Digital)：数字电路仿真软件，用于打开 `.dig` 文件
- [Icarus Verilog](http://iverilog.icarus.edu/)：Verilog 仿真器，用于运行测试台
- [香山开源处理器](https://github.com/OpenXiangShan/XiangShan)：本书的思想参照，选读内容见各章末尾的"香山一瞥"
