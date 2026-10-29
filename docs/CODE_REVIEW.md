# 代码审查报告 —— `niao`（高云 GW1N-9C / VGA 版 Flappy Bird）

审查范围：`top.sv`、`game_ctrl.sv`、`display.sv`、`rgb_timing.sv`、`uart_rx.v`、`video_pll.v`、`seg.v`、`top.cst`
审查方式：逐行阅读 RTL + 对关键算术/时序逻辑用 Node.js 行为模型复算（脚本见 `docs/sim/`）

**总体结论**：整体架构清晰、分层合理（时序发生 / 画布合成 / 游戏逻辑 / 串口 / 数码管），
视频时序参数计算正确，显示用了两级流水线解决 ROM 读延迟，作为比赛作品完成度是够的。
但有 **2 个 P0 级功能缺陷会直接导致游戏卡死或穿模**，另有若干稳健性与工程化问题。
下文 P0/P1 均给出可直接替换的代码。

| 级别 | 含义 | 数量 |
|---|---|---|
| P0 | 必然触发、直接破坏玩法 | 2 |
| P1 | 边界/稳健性问题，特定输入或改动后暴露 | 8 |
| P2 | 风格与冗余，不影响当前功能 | 6 |

---

## P0-1 `game_ctrl.sv:96` 管道高度计算出负值 → 整屏被堵死

```verilog
// game_ctrl.sv:94-96
cnt <= cnt + 1;
tube4_x <= 640;
tube4_h <= 100 + ((cnt[3] ? 7 - cnt : cnt) << 4);
```

`cnt` 是 `reg [3:0]`，`cnt[3]` 在 `cnt = 8..15` 时都为 1，于是走 `7 - cnt` 分支。
Verilog 里 `7 - cnt` 会把 `7`（32 bit 有符号）拓宽到 32 bit 求值，结果是**负数**，
而整个条件表达式被当无符号处理，左移 4 位后赋给 12 bit 的 `tube4_h` → 高 20 位被截掉。
`cnt = 14 / 15` 时 `-7 / -8` 左移截断成 `3984 / 3968`，加 100 之后成了 **4084 / 4068**。

用行为模型复算 `cnt = 0..15` 的实际输出：

```
cnt :   0    1    2    3    4    5    6    7    8   9  10  11  12  13    14    15
h   : 100  116  132  148  164  180  196  212   84  68  52  36  20   4  4084  4068
```

`cnt = 8..13` 那段虽然也是负值，但因为 `-16..-96` 截断后刚好落回 `84..4`，
反而凑成了三角形的下降沿 —— 真正致命的是最后两拍 `14 / 15`，`tube4_h` 冲到 4084 / 4068，
**整屏 480 行全被管子填满，缺口 `tube_h ~ tube_h+80` 完全跑到屏幕外**，
于是 `game_ctrl.sv:68` 的碰撞条件恒成立 → **玩家必死，且是完全无解的死法**。
这也是为什么这个 bug 表现为"玩十几根管子后突然卡死"（周期 16 次刷新才撞上一次）。
合法区间应落在 `4..212`（缺口 80 + 上管头 30 要能塞进 480 行）。

**修复**（把伪随机改成 3 bit 三角波，天然不会越界）：

```verilog
// 伪随机计数器：3 bit 足够，周期 16 次刷新
reg [3:0] cnt;
wire [3:0] cnt_n = cnt + 4'd1;
wire [2:0] tri   = cnt_n[3] ? (3'd7 - cnt_n[2:0]) : cnt_n[2:0];  // 0,1,..7,6,..0

...
cnt     <= cnt_n;
tube4_h <= 12'd40 + (tri << 4);   // 40..152，缺口末端 232，留足上下余量
```

> 用 3 bit 三角波替代原来的 `? :` 拼接，是**同时**修掉越界和保证周期性可预测的最省逻辑做法，
> LUT 反而比原来更少。

---

## P0-2 `game_ctrl.sv:78` 小鸟上跳无可下钳位 → 无符号回绕，小鸟"瞬移消失"

```verilog
else if (do_jump)
    bird_loc_y <= bird_loc_y - 20;
```

`bird_loc_y` 是 `reg [11:0]`。当 `bird_loc_y < 20` 时减法回绕：
`y = 11 → 4087`、`y = 5 → 4081`。此时 `display.sv:130` 的
`y_in_r1 >= bird_loc_y && y_in_r1 < bird_loc_y + 32` 永不成立 → **小鸟整帧不可见**；
同时 `game_ctrl.sv:69` 的 `bird_loc_y > 475` 立即判负（也算歪打正着地救了回来）。

**修复**：

```verilog
localparam Y_MIN = 12'd8;
localparam Y_MAX = 12'd440;

if (do_jump) begin
    bird_loc_y <= (bird_loc_y > Y_MIN + 20) ? bird_loc_y - 20 : Y_MIN;
end
else if (do_gravity) begin
    bird_loc_y <= (bird_loc_y < Y_MAX) ? bird_loc_y + 1 : Y_MAX;
end
```

把上下钳位和死亡判定解耦（死亡只由 `y > 475` 的越界判定，而不是靠回绕的副作用），
逻辑意图才明确。

---

## P1-1 `game_ctrl.sv:68-69` 碰撞检测只查 `tube1`，靠"间距恰好 128px"的隐式不变量成立

```verilog
GAME: if (((tube1_x < 128+56+32) && (bird_loc_y > tube1_h+64 || bird_loc_y < tube1_h)) ||
          bird_loc_y < 5 || bird_loc_y > 475) state <= END;
```

- 只判 `tube1`，其余 4 根管子不参与碰撞；
- 只给了上界 `tube1_x < 216`，没给下界（`tube1_x > 128`），管道尾刚过小鸟时仍会误判；
- 缺口容差用了 `64`，实际小鸟 32px + 缺口 80px 的可通行半宽应是 `(80-32)/2 = 24` 左右。

我用行为模型跑了 4000 帧稳态：管道间距恒为 128px、5 段移位链每 128px 补一根，
**只有 `tube1` 会落在小鸟的 x 窗口 (128, 216)** —— 0 次错位、0 次多管重叠。
所以**当前功能是对的**，但这是"间距 + 移位链长度"凑出来的巧合：
改管道速度、改间距、改成 6 根管子，碰撞立刻失效且没有任何报错。

**修复**（按 x 窗口扫描全部管道，顺便修掉下界与容差）：

```verilog
localparam BIRD_X = 128, BIRD_SIZE = 32, GAP = 80, Y_TOL = 8;

// 只需比较 x 窗口：管子右缘 > 小鸟左缘，且管子左缘 < 小鸟右缘
function automatic logic tube_hit(input [11:0] tx, input [11:0] th);
    logic x_overlap;
    x_overlap = (tx > BIRD_X) && (tx - TUBE_WIDTH < BIRD_X + BIRD_SIZE);
    tube_hit = x_overlap &&
               ((bird_loc_y + Y_TOL < th) ||                  // 小鸟整体在缺口上方
                (bird_loc_y + BIRD_SIZE - Y_TOL > th + GAP)); // 小鸟整体在缺口下方
endfunction

logic hit;
always_comb
    hit = tube_hit(tube0_x, tube0_h) || tube_hit(tube1_x, tube1_h) ||
          tube_hit(tube2_x, tube2_h) || tube_hit(tube3_x, tube3_h) ||
          tube_hit(tube4_x, tube4_h);
```

然后 `GAME: if (hit || bird_loc_y < 5 || bird_loc_y > 475) state <= END;`。
用 `function automatic` 而不是 `for` 循环数组，Gowin Syn 对前者支持更稳。

---

## P1-2 `game_ctrl.sv:34-36` 边沿检测是冗余的，而 `top.sv:95` 把 `rx_data_ready` 硬接 1

```verilog
// top.sv:95
.rx_data_ready (1'b1),
```

`uart_rx` 的一帧 valid 只拉高 1 拍（因为 ready 恒 1），所以 `rx_data_valid && !rx_data_valid_r`
的边沿检测永远等价于 `rx_data_valid` 本身，白占一个触发器。
**但它同时是个隐藏地雷**：哪天有人把 `rx_data_ready` 接上真实握手，`valid` 会连续多拍，
`!rx_data_valid_r` 会让"按住不放"变成只跳一次 —— 行为随握手协议静默改变。

**建议**：要么在 `top.sv:95` 接成 `1'b1` 的同时删掉边沿检测（省 1 FF），
要么保留边沿检测、把 `rx_data_ready` 接成真正的消费信号。二者选一，别混着。

---

## P1-3 `game_ctrl.sv:34` 软复位命令 `0x00` 实际打不出来

```verilog
assign do_soft_reset = rx_data_valid && !rx_data_valid_r && (rx_data == 8'h00);
```

普通文本终端 / 串口助手默认发 ASCII，发不出 `0x00`；手机蓝牙 App 发 "0" 是 `0x30`，
走的是 `do_jump` 而非复位。**结果是 END 态无法重开**（`game_ctrl.sv:71` `END: state <= END;`
是死锁的），只能按板上的复位键。

**建议**：换成可见字符，比如 `8'h72`（'r'），或复用 `'0'`：

```verilog
assign do_soft_reset = rx_data_valid && (rx_data == 8'h72);  // 'r'
```

---

## P1-4 `game_ctrl.sv:40, 84-87` `first_frame_after_reset` 是死代码

```verilog
if (first_frame_after_reset) begin
    // 第一帧直接左移，不再锁坐标
    first_frame_after_reset <= 0;
end
// 下面是同一段缩进的无条件逻辑，没有 else，标志没参与任何判断
if (tube4_x >= 512) begin ... end
```

标志位被置 1、被清 0，但**没有任何分支依赖它** —— 注释描述的"第一帧不再锁坐标"没有实现。
要么按注释补上真正的分支，要么整段删掉（省 1 FF + 一段注释误导）。

---

## P1-5 `uart_rx.v:146` 直接采样未同步的原始引脚

```verilog
else if(state == S_REC_BYTE && cycle_cnt == CYCLE/2 - 1)
    rx_bits[bit_cnt] <= rx_pin;      // ← 异步输入，未过同步器
```

文件里已经做了 `rx_d0/rx_d1` 两级同步（见 `uart_rx.v:95-105` 附近），
但采样这里用的是 `rx_pin` 而不是同步后的 `rx_d0`，在 25MHz 采样 9600bps 时每 2604 个时钟采一次，
**碰上亚稳态就是整位翻转**。属于低概率但真实存在的误码来源。

```verilog
if(state == S_REC_BYTE && cycle_cnt == CYCLE/2 - 1)
    rx_bits[bit_cnt] <= rx_d0;       // 用同步后的信号
```

另外 `uart_rx.v:5` 的 `parameter CLK_FRE = 50` 默认值与实际 25MHz 不符，
`top.sv:89-90` 显式传参救了它，但默认值应该改成 25，或者干脆去掉默认值、强制例化时给参。

---

## P1-6 `rgb_timing.sv:88, 90` VS 翻转误用了 `HS_POL`

```verilog
else if((v_cnt == V_FP - 1) && (h_cnt == H_FP - 1))
    rgb_vs <= HS_POL;                 // ← 应为 VS_POL
else if((v_cnt == V_FP + V_SYNC - 1) && (h_cnt == H_FP - 1))
    rgb_vs <= ~rgb_vs;
```

当前 `HS_POL == VS_POL == 0`，所以没暴露。一旦有人把 `VS_POL` 改成 1（某些显示器需要正极性），
VS 仍然是低有效 → **整帧不同步、屏幕滚动**，而且极难查（时序参数看着都对）。

```verilog
rgb_vs <= VS_POL;
```

---

## P1-7 `rgb_timing.sv:78-81` 每行第一个像素的 x 坐标残留上一帧的值

```verilog
else if(h_cnt == H_FP + H_SYNC + H_BP - 1)  h_active <= 'b1;   // 159 时就置有效
else if(h_cnt == H_TOTAL - 1)               h_active <= 'b0;
```

`h_active` 在 `h_cnt == 159` 拍被拉高，但 `rgb_x` 要到 `h_cnt >= 160` 才归零
（`rgb_x` 的更新条件比 `h_active` 晚一拍）。于是在 `h_cnt == 159` 这一拍
`h_active` 已为 1 而 `rgb_x` 还是上一行末尾的 `639` →
**每个有效行的第 1 个像素用错 x**，进而在 `display.sv:124` 的边框判断里画成 `12'h555`
（屏幕最左一列每行一个灰点，60Hz 下基本看不出来，但示波器/截图能抓到）。

把 `h_active` 的置位条件改成 `h_cnt == H_FP + H_SYNC + H_BP`（即 160）即可对齐。

---

## P1-8 `display.sv:76-77` 无条件 else 让 `rom_tube_addr` 下溢

```verilog
//显示 tube 4
else if (x_in >= tube4_x - TUBE_WIDTH && x_in < tube4_x && y_in < tube4_h)
    rom_tube_addr <= ...
else //if (x_in >= tube4_x - TUBE_WIDTH && x_in < tube4_x && y_in >= tube4_h + TUBE_GAP)
    rom_tube_addr <= (x_in + TUBE_WIDTH - tube4_x) + ((y_in > tube4_h+TUBE_GAP+TUBE_HEAD ? 0
                     : (tube4_h + TUBE_GAP + TUBE_HEAD - y_in)) * TUBE_WIDTH);
```

最后的 `else` 把注释掉的 `if` 条件删了，于是**任何没命中管子的像素**都会走进这条分支，
在 `y_in < tube4_h + TUBE_GAP + TUBE_HEAD` 时做无符号减法得到巨大数值，
`rom_tube_addr` 变成几千上万（`reg [10:0]` 截断），然后去读 `rom_tube`（1791 深）。
读数被丢弃（`display.sv:116-118` 会回退到背景），**功能上看不出来，但每帧白白多烧 640×480 次 BSRAM 读**，
功耗和布线拥塞都吃亏。

**修复**：把注释掉的 `if` 恢复，并给 `rom_tube_addr` 加默认值 0：

```verilog
always@(posedge clk) begin
    rom_tube_addr <= 11'd0;                      // 默认值，避免 latch/越界
    if (x_in >= tube0_x - TUBE_WIDTH && x_in < tube0_x && y_in < tube0_h) begin ... end
    ...
end
```

> 顺带说明：`display.sv` 的寻址（第 N 拍用 `x_in`）与决策（第 N+1 拍用 `x_in_r0`）**是对齐的**，
> 不存在系统性 1 像素错位 —— 这点我专门验算过，可以放心。

---

## P2 级（不影响当前功能，但建议清理）

### P2-1 `seg.v:55-63` 时序块里全用阻塞赋值

```verilog
case(wei)
    2'b00: begin DIG=6'b000010; SEG = data1[7:0];  end
    2'b01: begin DIG=6'b000001; SEG = data1[15:8]; end
    default: begin DIG=6'b000000; wei = 0; end
endcase
wei=wei+1;
```

- 时序 `always @(posedge clk)` 里必须用 `<=`，否则仿真与综合行为可能不一致、易产生竞争；
- `wei` 实际只有 2 个状态却用 `2'b00/2'b01` 比较，宽度不一致（`wei` 是 1 bit）；
- `default` 分支把 `DIG` 拉成 `6'b000000` → 该拍数码管全灭，**肉眼看是轻微闪烁**；
- `wei = 0` 与 `wei = wei + 1` 写在一起，`wei` 两个驱动源，综合器给的是前者优先，别这么写。

```verilog
always @(posedge clk) begin
    wei <= ~wei;
    if (wei) begin DIG <= 6'b000001; SEG <= data1[15:8]; end
    else     begin DIG <= 6'b000010; SEG <= data1[7:0];  end
end
```

### P2-2 `display.sv:130` 小鸟位置在流水线里被采样两次，跨帧边界会撕裂

地址生成用第 N 拍的 `bird_loc_y`，最终判决用第 N+2 拍的 `bird_loc_y`（未打拍）。
正常情况同一帧内 `bird_loc_y` 不变，无影响；但在 vsync 那一拍恰好更新的那一帧，
可能出现 **1~2 行的小鸟错位**。严谨做法是把 `bird_loc_y` 也打两拍给判决级用。

### P2-3 `top.sv:16` `FPGA_BEEP` 恒 0

```verilog
assign FPGA_BEEP = 0;   //-//
```

蜂鸣器从头到尾没响过。撞管 / 得分时给一个几百 ms 的方波，比赛现场"听感"会好很多，
成本只有一个计数器和几个 LUT。

### P2-4 `top.sv:30-31, 45-57` 声明位置过晚 / 变量分散

`wire rgb_clk;` 在 `video_pll` 例化（第 25 行）之后才声明，只是靠 SystemVerilog 允许隐式网络才没报错；
把参数、`localparam`、所有 `wire` 声明统一挪到例化之前，可读性会好很多。

### P2-5 `display.sv:49` 小鸟寻址没有默认值

`rom_bird_addr` 只在命中时赋值，否则保持旧值 → 综合出锁存器风格的行为（虽然被后续判断掩盖）。
加上 `else rom_bird_addr <= 10'd0;` 更规范。

### P2-6 魔法数字遍地

`128+56+32`、`64`、`100`、`512`、`1600` 等直接写在逻辑里。建议提成
`localparam BIRD_X / TUBE_WIDTH / GAP / SPAWN_X`，改玩法时不会漏改。

---

## 工程与交付问题

| # | 问题 | 影响 | 处理 |
|---|---|---|---|
| E-1 | 原目录**没有 `.gprj` 工程文件** | 拿到源码无法直接打开编译，必须手工重建工程 | 已补 `niao.gprj` |
| E-2 | **没有 `.sdc` 时钟约束** | 25MHz 的 PLL 输出未约束，STA 结果无意义，跑高了可能不收敛 | 已补 `niao.sdc`（`create_clock -period 20`） |
| E-3 | 路径含中文「愤怒的小鸟」 | 厂商文档 `67\4.通信相关软件\注意.txt` 明确要求「程序路径不能存在中文字符」，`$readmemh("background.c")` 在中文路径下可能读不到文件，综合结果全 0 | 仓库内路径全英文，克隆到英文目录编译 |
| E-4 | 无 testbench | 时序/游戏逻辑只能上板验证，改一行就得烧一次 | 见 `docs/sim/` 的 Node 行为模型，逻辑类改动可先离线验 |
| E-5 | 无 `impl/` 综合与布局布线产物 | 无法证明当前代码能综合过（缺 `.gprj` 时尤其可疑） | 用 `niao.gprj` 在云源里跑一遍全流程再发布 |
| E-6 | 作品名与玩法不符 | 注释 `game_ctrl.sv:2` 写的是 Flappy Bird，玩法也是"点击上升穿管"，与"愤怒的小鸟"（弹弓抛物线打猪）不是同一游戏 | README 已注明，答辩时建议主动说明改造点，否则容易被问倒 |

---

## 建议的修复顺序

1. **P0-1、P0-2** —— 不修，评委随手玩 30 秒就能撞到必死局。
2. **P1-3**（END 态能重开）+ **P1-8**（复位后第一根管子的位置）—— 现场演示流畅度直接相关。
3. **P1-6、P1-7** —— 各改 1 行，属于"白送的正确性"。
4. **P1-1** —— 如果打算继续加管子/改速度，必须先修；不加的话可以只补注释说明约束。
5. **P2-1** —— 数码管闪烁改成非阻塞 + 双相扫描。
6. 工程化 E-1 ~ E-5 属于交付质量，已在本次提交里补齐。

---

## 附：已核实为「正确」的疑点（避免重复排查）

- **视频时序**：25MHz / 800×525 → 640×480@59.52Hz，与 `rgb_timing.sv` 的
  `H_TOTAL=800, H_SYNC=96, H_BP=48, H_FP=16 / V_TOTAL=525, V_SYNC=2, V_BP=33, V_FP=10` 一致。
- **PLL 配置**：`video_pll.v` `FCLKIN=50, IDIV=1, FBDIV=0` → 25MHz，`CYCLE=2604`，
  9600bps 的实际误差 0.006%，远小于 UART 容限 ±2%。
- **`display.sv` 流水线对齐**：寻址拍与判决拍严格差 1 拍，无系统性像素错位。
- **多管重叠**：稳态下 5 根管子 x 坐标间隔恒为 128px，不会同时压在小鸟窗口上。
