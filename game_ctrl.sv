//=============================================================
//  game_ctrl.v  ——  Flappy Bird 控制（软复位后管子正常刷新）
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

reg rx_data_valid_r, vs_in_r;
always @(posedge clk) begin
    rx_data_valid_r <= rx_data_valid;
    vs_in_r         <= vs_in;
end

// 组合标志
logic do_soft_reset, do_jump, do_gravity;
assign do_soft_reset = rx_data_valid && !rx_data_valid_r && (rx_data == 8'h00);
assign do_jump       = rx_data_valid && !rx_data_valid_r && (rx_data != 8'h00);
assign do_gravity    = (state == GAME) && vs_in_r && !vs_in;

// 伪随机计数器
reg [3:0] cnt;
reg       first_frame_after_reset;   // 关键标志

//=============================================================
//  唯一 always 块：状态 + 小鸟 + 管子
//=============================================================
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        state                   <= START;
        bird_loc_y              <= 11'd240;
        first_frame_after_reset <= 1;
        // 管子初始值（只加载一次）
        tube0_x <= 1600; tube1_x <= 1600; tube2_x <= 1600; tube3_x <= 1600; tube4_x <= 700;
        tube0_h <= 0;    tube1_h <= 0;    tube2_h <= 0;    tube3_h <= 0;    tube4_h <= 100;
        cnt     <= 4'd1;
    end
    else if (do_soft_reset) begin
        state                   <= START;
        bird_loc_y              <= 11'd240;
        first_frame_after_reset <= 1;
        // 管子复位值（只加载一次）
        tube0_x <= 1600; tube1_x <= 1600; tube2_x <= 1600; tube3_x <= 1600; tube4_x <= 700;
        tube0_h <= 0;    tube1_h <= 0;    tube2_h <= 0;    tube3_h <= 0;    tube4_h <= 100;
        cnt     <= 4'd1;
    end
    else begin
        // ---- 状态机 ----
        case (state)
            START:  if (do_jump) state <= GAME; else state <= START;
            GAME:   if (((tube1_x < 128+56+32) && (bird_loc_y > tube1_h+64 || bird_loc_y < tube1_h)) ||
                        bird_loc_y < 5 || bird_loc_y > 475) state <= END;
                   else state <= GAME;
            END:    state <= END;
        endcase

        // ---- 小鸟 Y ----
        if (do_soft_reset)
            bird_loc_y <= 11'd240;
        else if (do_jump)
            bird_loc_y <= bird_loc_y - 20;
        else if (do_gravity)
            bird_loc_y <= bird_loc_y + 1;

        // ---- 管子逻辑 ----
        if (state == GAME && vs_in_r && !vs_in) begin
            if (first_frame_after_reset) begin
                // 第一帧直接左移，不再锁坐标
                first_frame_after_reset <= 0;
            end

            if (tube4_x >= 512) begin
                tube4_x <= tube4_x - 1; tube3_x <= tube3_x - 1; tube2_x <= tube2_x - 1;
                tube1_x <= tube1_x - 1; tube0_x <= tube0_x - 1;
            end
            else begin
                cnt <= cnt + 1;
                tube4_x <= 640;
                tube4_h <= 100 + ((cnt[3] ? 7 - cnt : cnt) << 4);
                tube3_x <= tube4_x; tube3_h <= tube4_h;
                tube2_x <= tube3_x; tube2_h <= tube3_h;
                tube1_x <= tube2_x; tube1_h <= tube2_h;
                tube0_x <= tube1_x; tube0_h <= tube1_h;
            end
        end
    end
end

endmodule