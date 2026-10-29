//=============================================================
//  game_ctrl.sv  ——  Flappy Bird 游戏控制
//  修订说明（相对原始版本）：
//    1. 管道缺口高度改用三角形序列，取值恒为 100..212，杜绝负值上溢
//       造成的 4084/4068 异常高度；
//    2. 小鸟上升做下边界钳位，杜绝 bird_loc_y 无符号回绕；
//    3. 游戏结束后按任意键即可重开，不再依赖无法从串口终端发出的 0x00；
//    4. 碰撞判定补上管道横向重叠的必要条件，避免管道已移过小鸟后仍误判死亡；
//    5. 删除未使用的 first_frame_after_reset 标志。
//=============================================================
module game_ctrl (
    input                  clk,
    input                  rst_n,
    input                  vs_in,
    input          [7:0]   rx_data,
    input                  rx_data_valid,
    output reg     [1:0]   state,
    output reg    [11:0]   bird_loc_y,
    output reg    [11:0]   tube0_x,
    output reg    [11:0]   tube1_x,
    output reg    [11:0]   tube2_x,
    output reg    [11:0]   tube3_x,
    output reg    [11:0]   tube4_x,
    output reg    [11:0]   tube0_h,
    output reg    [11:0]   tube1_h,
    output reg    [11:0]   tube2_h,
    output reg    [11:0]   tube3_h,
    output reg    [11:0]   tube4_h
);

enum logic [1:0] { START = 2'd0, GAME = 2'd1, END = 2'd2 } STATE;

//------------------------- 画面几何参数 --------------------------
localparam [11:0] BIRD_X_MIN = 12'd128;          // 小鸟左边
localparam [11:0] BIRD_X_MAX = 12'd160;          // 小鸟右边 = 128 + 32
localparam [11:0] TUBE_W     = 12'd56;           // 管道宽度
localparam [11:0] GAP_TOL    = 12'd64;           // 缺口纵向容差
localparam [11:0] Y_MIN      = 12'd5;            // 画面上下边界
localparam [11:0] Y_MAX      = 12'd475;
localparam [11:0] Y_STEP     = 12'd20;           // 每次点击上升量

reg rx_data_valid_r, vs_in_r;
always @(posedge clk) begin
    rx_data_valid_r <= rx_data_valid;
    vs_in_r         <= vs_in;
end

// 串口字节到达的上升沿（顶层 rx_data_ready 恒为 1，valid 只维持一拍）
wire rx_pulse = rx_data_valid && !rx_data_valid_r;

// 软复位：收到 0x00，或游戏结束后按任意键重开
// 跳跃：0x00 以外的任意字节（START 态按下即开始游戏）
logic do_soft_reset, do_jump, do_gravity;
assign do_soft_reset = rx_pulse && ((rx_data == 8'h00) || (state == END));
assign do_jump       = rx_pulse && (rx_data != 8'h00) && (state != END);
assign do_gravity    = (state == GAME) && vs_in_r && !vs_in;

//------------------------- 缺口高度序列 --------------------------
// cnt 每出现一根新管道加 1，4bit 自然回绕：
//   cnt[3]=0 → 索引 0..7 递增
//   cnt[3]=1 → 索引 7..0 递减
// 高度 = 100 + 索引*16，取值范围恒为 100..212，80px 缺口必落在 480 行画面内。
reg  [3:0] cnt;
wire [3:0] h_idx = cnt[3] ? (4'd15 - cnt) : cnt;

//------------------------- 死亡判定 --------------------------
// 管道占 [tube1_x-56, tube1_x)，小鸟占 [128,160)，两者相交 ⇔
// tube1_x-56 < 160 且 tube1_x > 128
wire tube1_overlap = (tube1_x > BIRD_X_MIN) && (tube1_x < (BIRD_X_MAX + TUBE_W));
wire hit_tube1     = tube1_overlap && ((bird_loc_y > (tube1_h + GAP_TOL)) ||
                                       (bird_loc_y < tube1_h));
wire is_dead       = hit_tube1 || (bird_loc_y < Y_MIN) || (bird_loc_y > Y_MAX);

//=============================================================
//  唯一时序块：状态 + 小鸟 + 管子
//=============================================================
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        state      <= START;
        bird_loc_y <= 12'd240;
        tube0_x <= 12'd1600; tube1_x <= 12'd1600; tube2_x <= 12'd1600;
        tube3_x <= 12'd1600; tube4_x <= 12'd700;
        tube0_h <= 12'd0;    tube1_h <= 12'd0;    tube2_h <= 12'd0;
        tube3_h <= 12'd0;    tube4_h <= 12'd100;
        cnt     <= 4'd1;
    end
    else if (do_soft_reset) begin
        state      <= START;
        bird_loc_y <= 12'd240;
        tube0_x <= 12'd1600; tube1_x <= 12'd1600; tube2_x <= 12'd1600;
        tube3_x <= 12'd1600; tube4_x <= 12'd700;
        tube0_h <= 12'd0;    tube1_h <= 12'd0;    tube2_h <= 12'd0;
        tube3_h <= 12'd0;    tube4_h <= 12'd100;
        cnt     <= 4'd1;
    end
    else begin
        // ---- 状态机 ----
        case (state)
            START: state <= do_jump ? GAME : START;
            GAME:  state <= is_dead ? END  : GAME;
            END:   state <= END;
        endcase

        // ---- 小鸟 Y：上升做下钳位；下降由上下边界判定兜底 ----
        if (do_jump)
            bird_loc_y <= (bird_loc_y > Y_STEP) ? (bird_loc_y - Y_STEP) : 12'd0;
        else if (do_gravity)
            bird_loc_y <= bird_loc_y + 12'd1;

        // ---- 管子：每帧左移 1 像素，移出屏幕后从右侧重新进入 ----
        if (state == GAME && vs_in_r && !vs_in) begin
            if (tube4_x >= 12'd512) begin
                tube0_x <= tube0_x - 12'd1;
                tube1_x <= tube1_x - 12'd1;
                tube2_x <= tube2_x - 12'd1;
                tube3_x <= tube3_x - 12'd1;
                tube4_x <= tube4_x - 12'd1;
            end
            else begin
                cnt     <= cnt + 4'd1;
                tube0_x <= tube1_x; tube0_h <= tube1_h;
                tube1_x <= tube2_x; tube1_h <= tube2_h;
                tube2_x <= tube3_x; tube2_h <= tube3_h;
                tube3_x <= tube4_x; tube3_h <= tube4_h;
                tube4_x <= 12'd640;
                tube4_h <= 12'd100 + (h_idx * 12'd16);
            end
        end
    end
end

endmodule
