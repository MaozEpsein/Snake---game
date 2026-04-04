// Snake Game - Top Module (Full Implementation)
// Hardware: Tang Nano 9K (Gowin GW1NR-9C) + Sipeed 7-inch LCD 800x480
//
// System clock: 27 MHz -> Pixel clock: 33 MHz (Gowin rPLL)
// Grid:  25 cols x 15 rows  (each cell = 32x32 px)
//
// Game states:
//   ST_IDLE      - title screen + last/best score, press 5 to start
//   ST_PLAYING   - active game
//   ST_GAME_OVER - "GAME OVER" + flash red, press S1 to restart
//
// Speed levels (frames per move @ 60 Hz):
//   Score  0- 4 -> 15 frames  (4.0 moves/sec)
//   Score  5- 9 -> 12 frames  (5.0 moves/sec)
//   Score 10-14 ->  9 frames  (6.7 moves/sec)
//   Score  15+  ->  6 frames  (10  moves/sec)
//
// Colors:  Head = bright green  | Body = dark green
//          Food = red           | HUD text = white (S/B/T at top-left)
//          Game-over bg = flash red | Text = white
//
// Keypad:  UP=2  DOWN=8  LEFT=4  RIGHT=6  PAUSE=5  RESTART=D(hold) | S1=reset
//
// Body storage: circular buffer (MAX_LEN=64 segments)
// Collision:    flat 375-bit presence map  body_map[row*25+col]
// Food RNG:     16-bit Galois LFSR

`timescale 1ns/1ps

module snake_top (
    input  wire        clk,         // 27 MHz  (pin 52)
    input  wire        reset_btn,   // S1 active-low (pin 4)

    // LCD interface
    output wire        LCD_CLK,
    output wire        LCD_HSYNC,
    output wire        LCD_VSYNC,
    output wire        LCD_DEN,
    output wire [4:0]  LCD_R,
    output wire [5:0]  LCD_G,
    output wire [4:0]  LCD_B,

    // Keypad 4x4
    output wire [3:0]  KEY_ROW,    // pins 66,65,64,63
    input  wire [3:0]  KEY_COL     // pins 82,81,80,79
);

    wire reset = ~reset_btn;

    wire clk_pixel, pll_locked;
    clock_divider u_pll (
        .clk_27MHz(clk), .reset(reset),
        .clk_pixel(clk_pixel), .pll_locked(pll_locked)
    );
    wire sys_reset = reset | ~pll_locked;

    wire vsync_int, de;
    wire [9:0] pixel_x, pixel_y;
    vga_controller u_lcd (
        .clk_pixel(clk_pixel), .reset(sys_reset),
        .hsync(LCD_HSYNC), .vsync(vsync_int),
        .de(de), .pixel_x(pixel_x), .pixel_y(pixel_y)
    );
    assign LCD_CLK  = clk_pixel;
    assign LCD_DEN  = de;
    assign LCD_VSYNC = vsync_int;

    wire key_up, key_down, key_left, key_right, key_pause, key_restart;
    keypad_scanner u_keypad (
        .clk(clk_pixel), .reset(sys_reset),
        .row(KEY_ROW), .col(KEY_COL),
        .key_up(key_up), .key_down(key_down),
        .key_left(key_left), .key_right(key_right),
        .key_pause(key_pause),
        .key_restart(key_restart)
    );

    // =========================================================
    //  Parameters
    // =========================================================
    localparam CELL_SIZE = 32;
    localparam GRID_COLS = 25;
    localparam GRID_ROWS = 15;
    localparam BORDER    = 1;
    localparam MAX_LEN   = 64;

    localparam DIR_RIGHT = 2'd0;
    localparam DIR_LEFT  = 2'd1;
    localparam DIR_UP    = 2'd2;
    localparam DIR_DOWN  = 2'd3;

    localparam ST_IDLE      = 2'd0;
    localparam ST_PLAYING   = 2'd1;
    localparam ST_GAME_OVER = 2'd2;
    localparam RESTART_HOLD_FRAMES = 7'd60;

    // =========================================================
    //  Cell-index: row*25 + col (0..374)
    // =========================================================
    function [8:0] cidx;
        input [3:0] r;
        input [4:0] c;
        cidx = ({5'b0,r} << 4) + ({5'b0,r} << 3) + {5'b0,r} + {4'b0,c};
    endfunction

    // =========================================================
    //  Character font  (5x7 pixels, 35-bit bitmap)
    //  ch 0-9   = digits
    //  ch 10-35 = letters A-Z
    //  ch 36    = space
    // =========================================================
    function [34:0] char_bitmap;
        input [5:0] ch;
        case (ch)
            6'd0:  char_bitmap = 35'b01110_10001_10001_10001_10001_10001_01110;
            6'd1:  char_bitmap = 35'b00100_01100_00100_00100_00100_00100_01110;
            6'd2:  char_bitmap = 35'b01110_10001_00001_00110_01000_10000_11111;
            6'd3:  char_bitmap = 35'b11110_00001_00001_01110_00001_00001_11110;
            6'd4:  char_bitmap = 35'b10001_10001_10001_11111_00001_00001_00001;
            6'd5:  char_bitmap = 35'b11111_10000_10000_11110_00001_00001_11110;
            6'd6:  char_bitmap = 35'b01110_10000_10000_11110_10001_10001_01110;
            6'd7:  char_bitmap = 35'b11111_00001_00001_00010_00100_00100_00100;
            6'd8:  char_bitmap = 35'b01110_10001_10001_01110_10001_10001_01110;
            6'd9:  char_bitmap = 35'b01110_10001_10001_01111_00001_00001_01110;
            6'd10: char_bitmap = 35'b01110_10001_10001_11111_10001_10001_10001; // A
            6'd11: char_bitmap = 35'b11110_10001_10001_11110_10001_10001_11110; // B
            6'd12: char_bitmap = 35'b01111_10000_10000_10000_10000_10000_01111; // C
            6'd13: char_bitmap = 35'b11110_10001_10001_10001_10001_10001_11110; // D
            6'd14: char_bitmap = 35'b11111_10000_10000_11110_10000_10000_11111; // E
            6'd15: char_bitmap = 35'b11111_10000_10000_11110_10000_10000_10000; // F
            6'd16: char_bitmap = 35'b01111_10000_10000_10011_10001_10001_01111; // G
            6'd17: char_bitmap = 35'b10001_10001_10001_11111_10001_10001_10001; // H
            6'd18: char_bitmap = 35'b01110_00100_00100_00100_00100_00100_01110; // I
            6'd19: char_bitmap = 35'b00111_00001_00001_00001_10001_10001_01110; // J
            6'd20: char_bitmap = 35'b10001_10010_10100_11000_10100_10010_10001; // K
            6'd21: char_bitmap = 35'b10000_10000_10000_10000_10000_10000_11111; // L
            6'd22: char_bitmap = 35'b10001_11011_10101_10001_10001_10001_10001; // M
            6'd23: char_bitmap = 35'b10001_11001_10101_10011_10001_10001_10001; // N
            6'd24: char_bitmap = 35'b01110_10001_10001_10001_10001_10001_01110; // O
            6'd25: char_bitmap = 35'b11110_10001_10001_11110_10000_10000_10000; // P
            6'd26: char_bitmap = 35'b01110_10001_10001_10001_10101_10010_01101; // Q
            6'd27: char_bitmap = 35'b11110_10001_10001_11110_10100_10010_10001; // R
            6'd28: char_bitmap = 35'b01110_10000_10000_01110_00001_00001_01110; // S
            6'd29: char_bitmap = 35'b11111_00100_00100_00100_00100_00100_00100; // T
            6'd30: char_bitmap = 35'b10001_10001_10001_10001_10001_10001_01110; // U
            6'd31: char_bitmap = 35'b10001_10001_10001_10001_01010_01010_00100; // V
            6'd32: char_bitmap = 35'b10001_10001_10101_10101_10101_11011_10001; // W
            6'd33: char_bitmap = 35'b10001_10001_01010_00100_01010_10001_10001; // X
            6'd34: char_bitmap = 35'b10001_10001_01010_00100_00100_00100_00100; // Y
            6'd35: char_bitmap = 35'b11111_00001_00010_00100_01000_10000_11111; // Z
            default: char_bitmap = 35'b0;
        endcase
    endfunction

    function [4:0] font_row_bits;
        input [34:0] bm;
        input [2:0]  r;
        case (r)
            3'd0: font_row_bits = bm[34:30];
            3'd1: font_row_bits = bm[29:25];
            3'd2: font_row_bits = bm[24:20];
            3'd3: font_row_bits = bm[19:15];
            3'd4: font_row_bits = bm[14:10];
            3'd5: font_row_bits = bm[9:5];
            3'd6: font_row_bits = bm[4:0];
            default: font_row_bits = 5'b0;
        endcase
    endfunction

    // Returns 1 if pixel (px,py) hits glyph at cell (cx,cy), scale=2
    function text_pix;
        input [9:0] px, py;
        input [9:0] cx, cy;
        input [5:0] ch;
        reg [9:0]  rx, ry;
        reg [2:0]  fc, fr_v;
        reg [34:0] bm;
        reg [4:0]  rbits;
        begin
            rx = px - cx;
            ry = py - cy;
            if (rx < 10'd10 && ry < 10'd14 && ch != 6'd36) begin
                fc    = rx[3:1];
                fr_v  = ry[3:1];
                bm    = char_bitmap(ch);
                rbits = font_row_bits(bm, fr_v);
                text_pix = rbits[4 - fc];
            end else
                text_pix = 1'b0;
        end
    endfunction

    // =========================================================
    //  Snake Body Circular Buffer (MAX_LEN=64)
    // =========================================================
    reg [4:0] body_col [0:MAX_LEN-1];
    reg [3:0] body_row [0:MAX_LEN-1];
    reg [5:0] head_ptr;
    reg [6:0] snake_len;

    wire [5:0] tail_ptr = head_ptr - snake_len[5:0] + 6'd1;
    wire [4:0] head_col = body_col[head_ptr];
    wire [3:0] head_row = body_row[head_ptr];

    // =========================================================
    //  Body Presence Map (375 bits)
    // =========================================================
    reg [374:0] body_map;

    // =========================================================
    //  Game State
    // =========================================================
    reg [1:0]  game_state;
    reg [1:0]  direction;
    reg [3:0]  frame_cnt;
    reg [7:0]  score;
    reg [7:0]  last_score;
    reg [7:0]  best_score = 8'd0;
    reg [4:0]  flash_cnt;
    reg        paused;
    reg        key_pause_prev;
    reg [6:0]  restart_hold_cnt;
    reg        restart_latched;
    reg [5:0]  sec_frame_cnt;
    reg [3:0]  time_m_tens;
    reg [3:0]  time_m_ones;
    reg [3:0]  time_s_tens;
    reg [3:0]  time_s_ones;

    reg  vsync_d;
    wire frame_tick = ~vsync_d & vsync_int;
    wire start_pressed = key_pause;
    wire pause_pressed = key_pause & ~key_pause_prev;

    // =========================================================
    //  Dynamic Speed
    // =========================================================
    reg [3:0] move_speed;
    always @(*) begin
        if      (score >= 8'd15) move_speed = 4'd6;
        else if (score >= 8'd10) move_speed = 4'd9;
        else if (score >= 8'd5)  move_speed = 4'd12;
        else                     move_speed = 4'd15;
    end

    // =========================================================
    //  Food
    // =========================================================
    reg [4:0] food_col;
    reg [3:0] food_row;
    reg       food_active;

    reg  [15:0] lfsr;
    wire [15:0] lfsr_next = {1'b0, lfsr[15:1]} ^ (lfsr[0] ? 16'hB400 : 16'h0);

    wire [4:0] fc_col = (lfsr[4:0]  < 5'd25) ? lfsr[4:0]  : lfsr[4:0]  - 5'd25;
    wire [3:0] fc_row = (lfsr[11:8] < 4'd15) ? lfsr[11:8] : lfsr[11:8] - 4'd15;

    // =========================================================
    //  Next-Head Position (combinational)
    // =========================================================
    reg [4:0] next_col;
    reg [3:0] next_row;
    always @(*) begin
        case (direction)
            DIR_RIGHT: begin next_col = (head_col==5'd24) ? 5'd0  : head_col+5'd1; next_row = head_row; end
            DIR_LEFT:  begin next_col = (head_col==5'd0)  ? 5'd24 : head_col-5'd1; next_row = head_row; end
            DIR_UP:    begin next_col = head_col; next_row = (head_row==4'd0)  ? 4'd14 : head_row-4'd1; end
            default:   begin next_col = head_col; next_row = (head_row==4'd14) ? 4'd0  : head_row+4'd1; end
        endcase
    end

    wire [8:0] next_cidx = cidx(next_row, next_col);
    wire [8:0] tail_cidx = cidx(body_row[tail_ptr], body_col[tail_ptr]);

    wire eating_food = food_active && (next_col == food_col) && (next_row == food_row);
    wire hit_body    = body_map[next_cidx] &&
                       (eating_food || (next_cidx != tail_cidx));

    // =========================================================
    //  Game Logic (sequential)
    // =========================================================
    always @(posedge clk_pixel or posedge sys_reset) begin
        if (sys_reset) begin
            vsync_d     <= 1'b1;
            game_state  <= ST_IDLE;
            direction   <= DIR_RIGHT;
            frame_cnt   <= 4'd0;
            score       <= 8'd0;
            last_score  <= 8'd0;
            flash_cnt   <= 5'd0;
            paused      <= 1'b0;
            key_pause_prev <= 1'b0;
            restart_hold_cnt <= 7'd0;
            restart_latched  <= 1'b0;
            sec_frame_cnt <= 6'd0;
            time_m_tens  <= 4'd0;
            time_m_ones  <= 4'd0;
            time_s_tens  <= 4'd0;
            time_s_ones  <= 4'd0;
            lfsr        <= 16'hACE1;
            food_active <= 1'b1;
            food_col    <= 5'd20;
            food_row    <= 4'd7;

            head_ptr  <= 6'd0;
            snake_len <= 7'd3;
            body_col[0]  <= 5'd12;  body_row[0]  <= 4'd7;
            body_col[63] <= 5'd11;  body_row[63] <= 4'd7;
            body_col[62] <= 5'd10;  body_row[62] <= 4'd7;

            body_map      <= 375'b0;
            body_map[187] <= 1'b1;   // cidx(7,12)
            body_map[186] <= 1'b1;   // cidx(7,11)
            body_map[185] <= 1'b1;   // cidx(7,10)

        end else begin
            lfsr    <= lfsr_next;
            vsync_d <= vsync_int;

            if (frame_tick) begin
                flash_cnt <= flash_cnt + 5'd1;
                key_pause_prev <= key_pause;

                if (key_restart) begin
                    if (restart_hold_cnt < RESTART_HOLD_FRAMES)
                        restart_hold_cnt <= restart_hold_cnt + 7'd1;
                end else begin
                    restart_hold_cnt <= 7'd0;
                    restart_latched  <= 1'b0;
                end

                if ((game_state != ST_IDLE) && key_restart && !restart_latched &&
                    (restart_hold_cnt == RESTART_HOLD_FRAMES - 7'd1)) begin
                    restart_latched  <= 1'b1;

                    if (game_state == ST_PLAYING)
                        last_score <= score;

                    game_state  <= ST_IDLE;
                    direction   <= DIR_RIGHT;
                    frame_cnt   <= 4'd0;
                    score       <= 8'd0;
                    flash_cnt   <= 5'd0;
                    paused      <= 1'b0;
                    key_pause_prev <= 1'b0;
                    sec_frame_cnt <= 6'd0;
                    time_m_tens  <= 4'd0;
                    time_m_ones  <= 4'd0;
                    time_s_tens  <= 4'd0;
                    time_s_ones  <= 4'd0;
                    food_active <= 1'b1;
                    food_col    <= 5'd20;
                    food_row    <= 4'd7;

                    head_ptr  <= 6'd0;
                    snake_len <= 7'd3;
                    body_col[0]  <= 5'd12;  body_row[0]  <= 4'd7;
                    body_col[63] <= 5'd11;  body_row[63] <= 4'd7;
                    body_col[62] <= 5'd10;  body_row[62] <= 4'd7;

                    body_map      <= 375'b0;
                    body_map[187] <= 1'b1;
                    body_map[186]    <= 1'b1;
                    body_map[185] <= 1'b1;
                end else begin

                case (game_state)

                    ST_IDLE: begin
                        paused <= 1'b0;
                        if (start_pressed) begin
                            game_state <= ST_PLAYING;
                            direction  <= DIR_RIGHT;
                            frame_cnt  <= 4'd0;
                            score      <= 8'd0;
                            sec_frame_cnt <= 6'd0;
                            time_m_tens  <= 4'd0;
                            time_m_ones  <= 4'd0;
                            time_s_tens  <= 4'd0;
                            time_s_ones  <= 4'd0;
                        end
                    end

                    ST_PLAYING: begin
                        if (pause_pressed)
                            paused <= ~paused;

                        if (!paused && !pause_pressed) begin
                            // 60 frame ticks ~= 1 second at 60 Hz
                            if (sec_frame_cnt == 6'd59) begin
                                sec_frame_cnt <= 6'd0;
                                if (time_s_ones == 4'd9) begin
                                    time_s_ones <= 4'd0;
                                    if (time_s_tens == 4'd5) begin
                                        time_s_tens <= 4'd0;
                                        if (time_m_ones == 4'd9) begin
                                            time_m_ones <= 4'd0;
                                            if (time_m_tens != 4'd9)
                                                time_m_tens <= time_m_tens + 4'd1;
                                        end else begin
                                            time_m_ones <= time_m_ones + 4'd1;
                                        end
                                    end else begin
                                        time_s_tens <= time_s_tens + 4'd1;
                                    end
                                end else begin
                                    time_s_ones <= time_s_ones + 4'd1;
                                end
                            end else begin
                                sec_frame_cnt <= sec_frame_cnt + 6'd1;
                            end

                            if      (key_up    && direction != DIR_DOWN)  direction <= DIR_UP;
                            else if (key_down  && direction != DIR_UP)    direction <= DIR_DOWN;
                            else if (key_left  && direction != DIR_RIGHT) direction <= DIR_LEFT;
                            else if (key_right && direction != DIR_LEFT)  direction <= DIR_RIGHT;

                            frame_cnt <= frame_cnt + 4'd1;
                            if (frame_cnt == move_speed - 4'd1) begin
                                frame_cnt <= 4'd0;
                                if (hit_body) begin
                                    last_score <= score;
                                    game_state <= ST_GAME_OVER;
                                    paused <= 1'b0;
                                end else begin
                                    head_ptr                  <= head_ptr + 6'd1;
                                    body_col[head_ptr + 6'd1] <= next_col;
                                    body_row[head_ptr + 6'd1] <= next_row;
                                    body_map[next_cidx]       <= 1'b1;
                                    if (eating_food) begin
                                        snake_len   <= snake_len + 7'd1;
                                        score       <= score + 8'd1;
                                        if (score + 8'd1 > best_score)
                                            best_score <= score + 8'd1;
                                        food_active <= 1'b0;
                                    end else begin
                                        if (tail_cidx != next_cidx)
                                            body_map[tail_cidx] <= 1'b0;
                                    end
                                end
                            end

                            if (!food_active && !body_map[cidx(fc_row, fc_col)]) begin
                                food_row    <= fc_row;
                                food_col    <= fc_col;
                                food_active <= 1'b1;
                            end
                        end
                    end

                    default: begin
                        // ST_GAME_OVER: wait for sys_reset (S1)
                    end

                endcase
                end
            end
        end
    end

    // =========================================================
    //  Rendering (combinational, per-pixel)
    // =========================================================

    wire [4:0] cur_col  = pixel_x[9:5];
    wire [4:0] cur_row5 = pixel_y[9:5];
    wire [3:0] cur_row  = cur_row5[3:0];
    wire [8:0] cur_cidx = cidx(cur_row, cur_col);

    wire in_interior = de &&
        (pixel_x[4:0] >= BORDER) && (pixel_x[4:0] < CELL_SIZE - BORDER) &&
        (pixel_y[4:0] >= BORDER) && (pixel_y[4:0] < CELL_SIZE - BORDER);

    wire is_head = (cur_col == head_col) && (cur_row == head_row);
    wire is_body = body_map[cur_cidx] && !is_head;
    wire is_food = food_active && (cur_col == food_col) && (cur_row == food_row);
    wire flash_on = flash_cnt[4];

    // --- Compact HUD (top-left): S###  B###  TMM:SS ---
    wire [3:0] sc_h = score / 8'd100;
    wire [3:0] sc_t = (score - sc_h * 8'd100) / 8'd10;
    wire [3:0] sc_u =  score - sc_h * 8'd100 - sc_t * 8'd10;

    wire [3:0] bs_h = best_score / 8'd100;
    wire [3:0] bs_t = (best_score - bs_h * 8'd100) / 8'd10;
    wire [3:0] bs_u =  best_score - bs_h * 8'd100 - bs_t * 8'd10;

    wire [3:0] ls_h = last_score / 8'd100;
    wire [3:0] ls_t = (last_score - ls_h * 8'd100) / 8'd10;
    wire [3:0] ls_u =  last_score - ls_h * 8'd100 - ls_t * 8'd10;

    wire hud_text_pixel = de && (game_state != ST_IDLE) && (
        // S###
        text_pix(pixel_x,pixel_y, 10'd8,   10'd8,  6'd28) ||
        text_pix(pixel_x,pixel_y, 10'd20,  10'd8,  {2'b0, sc_h}) ||
        text_pix(pixel_x,pixel_y, 10'd32,  10'd8,  {2'b0, sc_t}) ||
        text_pix(pixel_x,pixel_y, 10'd44,  10'd8,  {2'b0, sc_u}) ||

        // B###
        text_pix(pixel_x,pixel_y, 10'd68,  10'd8,  6'd11) ||
        text_pix(pixel_x,pixel_y, 10'd80,  10'd8,  {2'b0, bs_h}) ||
        text_pix(pixel_x,pixel_y, 10'd92,  10'd8,  {2'b0, bs_t}) ||
        text_pix(pixel_x,pixel_y, 10'd104, 10'd8,  {2'b0, bs_u}) ||

        // TMMSS
        text_pix(pixel_x,pixel_y, 10'd140, 10'd8,  6'd29) ||
        text_pix(pixel_x,pixel_y, 10'd152, 10'd8,  {2'b0, time_m_tens}) ||
        text_pix(pixel_x,pixel_y, 10'd164, 10'd8,  {2'b0, time_m_ones}) ||
        text_pix(pixel_x,pixel_y, 10'd184, 10'd8,  {2'b0, time_s_tens}) ||
        text_pix(pixel_x,pixel_y, 10'd196, 10'd8,  {2'b0, time_s_ones})
    );

    wire hud_colon_pixel = de && (game_state != ST_IDLE) &&
        (pixel_x >= 10'd176) && (pixel_x < 10'd178) &&
        (((pixel_y >= 10'd11) && (pixel_y < 10'd13)) ||
         ((pixel_y >= 10'd17) && (pixel_y < 10'd19)));

    wire score_pixel = hud_text_pixel || hud_colon_pixel;

    // --- Title screen: "SNAKE" y=180, "PRESS 5" y=240, LAST/BEST below ---
    // Each char 10px wide x 14px tall (5x7 at scale 2), gap=2px
    // "SNAKE" 5 chars: width=58px, start_x=371
    // "PRESS S1" 8 chars: width=94px, start_x=353
    wire idle_pixel = de && (game_state == ST_IDLE) && (
        text_pix(pixel_x,pixel_y, 10'd371,10'd180, 6'd28) ||  // S
        text_pix(pixel_x,pixel_y, 10'd383,10'd180, 6'd23) ||  // N
        text_pix(pixel_x,pixel_y, 10'd395,10'd180, 6'd10) ||  // A
        text_pix(pixel_x,pixel_y, 10'd407,10'd180, 6'd20) ||  // K
        text_pix(pixel_x,pixel_y, 10'd419,10'd180, 6'd14) ||  // E
        text_pix(pixel_x,pixel_y, 10'd359,10'd240, 6'd25) ||  // P
        text_pix(pixel_x,pixel_y, 10'd371,10'd240, 6'd27) ||  // R
        text_pix(pixel_x,pixel_y, 10'd383,10'd240, 6'd14) ||  // E
        text_pix(pixel_x,pixel_y, 10'd395,10'd240, 6'd28) ||  // S
        text_pix(pixel_x,pixel_y, 10'd407,10'd240, 6'd28) ||  // S
        text_pix(pixel_x,pixel_y, 10'd431,10'd240, {2'b0,4'd5}) || // 5 (space at 419)

        // LAST ###
        text_pix(pixel_x,pixel_y, 10'd329,10'd300, 6'd21) ||  // L
        text_pix(pixel_x,pixel_y, 10'd341,10'd300, 6'd10) ||  // A
        text_pix(pixel_x,pixel_y, 10'd353,10'd300, 6'd28) ||  // S
        text_pix(pixel_x,pixel_y, 10'd365,10'd300, 6'd29) ||  // T
        text_pix(pixel_x,pixel_y, 10'd389,10'd300, {2'b0, ls_h}) ||
        text_pix(pixel_x,pixel_y, 10'd401,10'd300, {2'b0, ls_t}) ||
        text_pix(pixel_x,pixel_y, 10'd413,10'd300, {2'b0, ls_u}) ||

        // BEST ###
        text_pix(pixel_x,pixel_y, 10'd329,10'd324, 6'd11) ||  // B
        text_pix(pixel_x,pixel_y, 10'd341,10'd324, 6'd14) ||  // E
        text_pix(pixel_x,pixel_y, 10'd353,10'd324, 6'd28) ||  // S
        text_pix(pixel_x,pixel_y, 10'd365,10'd324, 6'd29) ||  // T
        text_pix(pixel_x,pixel_y, 10'd389,10'd324, {2'b0, bs_h}) ||
        text_pix(pixel_x,pixel_y, 10'd401,10'd324, {2'b0, bs_t}) ||
        text_pix(pixel_x,pixel_y, 10'd413,10'd324, {2'b0, bs_u})
    );

    // --- Game over: "GAME OVER" centered y=220 ---
    // 9 chars: width=106px, start_x=347
    wire gameover_pixel = de && (game_state == ST_GAME_OVER) && (
        text_pix(pixel_x,pixel_y, 10'd347,10'd220, 6'd16) ||  // G
        text_pix(pixel_x,pixel_y, 10'd359,10'd220, 6'd10) ||  // A
        text_pix(pixel_x,pixel_y, 10'd371,10'd220, 6'd22) ||  // M
        text_pix(pixel_x,pixel_y, 10'd383,10'd220, 6'd14) ||  // E
        text_pix(pixel_x,pixel_y, 10'd407,10'd220, 6'd24) ||  // O (space at 395)
        text_pix(pixel_x,pixel_y, 10'd419,10'd220, 6'd31) ||  // V
        text_pix(pixel_x,pixel_y, 10'd431,10'd220, 6'd14) ||  // E
        text_pix(pixel_x,pixel_y, 10'd443,10'd220, 6'd27));    // R

    // --- Pause overlay: "PAUSE" centered y=220 ---
    wire pause_pixel = de && (game_state == ST_PLAYING) && paused && (
        text_pix(pixel_x,pixel_y, 10'd371,10'd220, 6'd25) ||  // P
        text_pix(pixel_x,pixel_y, 10'd383,10'd220, 6'd10) ||  // A
        text_pix(pixel_x,pixel_y, 10'd395,10'd220, 6'd30) ||  // U
        text_pix(pixel_x,pixel_y, 10'd407,10'd220, 6'd28) ||  // S
        text_pix(pixel_x,pixel_y, 10'd419,10'd220, 6'd14));   // E

    // =========================================================
    //  Pixel color mux
    //  Priority: text overlay > cell border > state-based color
    // =========================================================
    reg [4:0] pix_r;
    reg [5:0] pix_g;
    reg [4:0] pix_b;

    always @(*) begin
        if (score_pixel || idle_pixel || gameover_pixel || pause_pixel) begin
            pix_r = 5'b11111;  pix_g = 6'b111111;  pix_b = 5'b11111;
        end else if (!in_interior) begin
            pix_r = 5'b00000;  pix_g = 6'b000000;  pix_b = 5'b00000;
        end else begin
            case (game_state)
                ST_IDLE: begin
                    pix_r = 5'b00000;  pix_g = 6'b000100;  pix_b = 5'b00110;
                end
                ST_PLAYING: begin
                    if (is_head)      begin pix_r = 5'b00000; pix_g = 6'b111111; pix_b = 5'b00000; end
                    else if (is_body) begin pix_r = 5'b00000; pix_g = 6'b011000; pix_b = 5'b00000; end
                    else if (is_food) begin pix_r = 5'b11111; pix_g = 6'b000000; pix_b = 5'b00000; end
                    else              begin pix_r = 5'b00000; pix_g = 6'b000000; pix_b = 5'b00000; end
                end
                default: begin  // ST_GAME_OVER
                    pix_r = flash_on ? 5'b11111 : 5'b00110;
                    pix_g = 6'b000000;
                    pix_b = 5'b00000;
                end
            endcase
        end
    end

    assign LCD_R = pix_r;
    assign LCD_G = pix_g;
    assign LCD_B = pix_b;

endmodule
