// Testbench - Snake Game (Tang Nano 9K + Sipeed 7-inch LCD 800x480)
//
// Phase 1 - ST_IDLE:       white title text, no green pixels
// Phase 2 - Idle start gate: only key "5" starts, arrows must not start
// Phase 3 - ST_PLAYING:    head green, food red, score/HUD visible, no bad pixels
// Phase 4 - Movement:      head position changes after one forced game move
// Phase 5 - U-turn block:  pressing opposite direction does not reverse snake
// Phase 6 - Pause/Resume:  key "5" toggles paused, freezes and resumes movement
// Phase 7 - Restart (D):   short press ignored, long press (~1s) restarts game
// Phase 8 - Game Over:     hit_body=1 -> transitions to ST_GAME_OVER + LAST score latched
// Phase 9 - GO visuals:    red/dark-red background + GAME OVER text, no green
// Phase 10 - Reset:        S1 returns to ST_IDLE, title visible
//
// Acceleration technique (Phases 3, 4):
//   Instead of waiting 15 frames for a game move, force dut.frame_cnt = 14
//   immediately before a frame_tick.  The move fires on that same tick.
//
// Build & run:
//   iverilog -g2005 -o snake_sim.vvp clock_divider.v vga_controller.v \
//            keypad_scanner.v snake_top.v snake_top_tb.v
//   vvp snake_sim.vvp

`timescale 1ns/1ps

module snake_top_tb;

    reg clk       = 0;
    reg reset_btn = 0;
    reg [3:0] KEY_COL = 4'b0000;

    wire        LCD_CLK, LCD_HSYNC, LCD_VSYNC, LCD_DEN;
    wire [4:0]  LCD_R;
    wire [5:0]  LCD_G;
    wire [4:0]  LCD_B;
    wire [3:0]  KEY_ROW;

    snake_top dut (
        .clk(clk), .reset_btn(reset_btn),
        .LCD_CLK(LCD_CLK), .LCD_HSYNC(LCD_HSYNC), .LCD_VSYNC(LCD_VSYNC),
        .LCD_DEN(LCD_DEN), .LCD_R(LCD_R), .LCD_G(LCD_G), .LCD_B(LCD_B),
        .KEY_ROW(KEY_ROW), .KEY_COL(KEY_COL)
    );

    always #18.5 clk = ~clk;

    integer vsync_count   = 0;
    integer white_pixels  = 0;
    integer green_pixels  = 0;
    integer red_pixels    = 0;   // bright red: R=11111 G=0 B=0
    integer anyred_pixels = 0;   // any red-only: R>0 G=0 B=0  (covers dark flash too)
    integer bad_pixels    = 0;

    always @(negedge LCD_VSYNC) vsync_count = vsync_count + 1;

    always @(posedge LCD_CLK) begin
        if (LCD_DEN && LCD_R==5'b11111 && LCD_G==6'b111111 && LCD_B==5'b11111)
            white_pixels  = white_pixels  + 1;
        if (LCD_DEN && LCD_R==5'b00000 && LCD_G==6'b111111 && LCD_B==5'b00000)
            green_pixels  = green_pixels  + 1;
        if (LCD_DEN && LCD_R==5'b11111 && LCD_G==6'b000000 && LCD_B==5'b00000)
            red_pixels    = red_pixels    + 1;
        if (LCD_DEN && LCD_G==6'b000000 && LCD_B==5'b00000 && LCD_R!=5'b0)
            anyred_pixels = anyred_pixels + 1;
        if (!LCD_DEN && (LCD_R!=5'b0 || LCD_G!=6'b0 || LCD_B!=5'b0))
            bad_pixels    = bad_pixels    + 1;
    end

    task reset_counters;
        begin
            white_pixels  = 0; green_pixels  = 0;
            red_pixels    = 0; anyred_pixels = 0;
            vsync_count   = 0; bad_pixels    = 0;
        end
    endtask

    // Force a game move immediately by setting frame_cnt to move_speed-1
    // right before the next frame_tick.
    task force_one_move;
        begin
            force dut.frame_cnt = 4'd14;   // move_speed-1 at score 0
            @(posedge dut.frame_tick);
            #60;                           // 2 clk_pixel periods - let NBA settle
            release dut.frame_cnt;
        end
    endtask

    initial begin
        $dumpfile("snake_top_tb.vcd");
        $dumpvars(0, snake_top_tb);
        #500_000;
        $dumpoff;
    end

    localparam ONE_FRAME = 17_000_000;

    initial begin
        $display("=== Snake Game Testbench ===");

        reset_btn = 1'b0; #200;
        reset_btn = 1'b1; #100;
        reset_counters;

        // ---- Phase 1: ST_IDLE (2 frames, no key pressed) ----
        #(2 * ONE_FRAME);
        $display("--- Phase 1: ST_IDLE ---");
        $display("VSYNC  : %0d (expect 2)",  vsync_count);
        $display("White  : %0d (expect >0 title text)", white_pixels);
        $display("Green  : %0d (expect 0  no game yet)", green_pixels);

        if (vsync_count >= 1 && vsync_count <= 3)
            $display("PASS: VSYNC timing OK");
        else
            $display("FAIL: VSYNC wrong - got %0d", vsync_count);

        if (white_pixels > 0)
            $display("PASS: Title text visible");
        else
            $display("FAIL: No title text pixels");

        if (green_pixels == 0)
            $display("PASS: No game pixels in IDLE");
        else
            $display("FAIL: Unexpected green in IDLE: %0d", green_pixels);

        reset_counters;

        // ---- Phase 2: Idle start gate (only key 5 starts) ----
        $display("--- Phase 2: Idle start gate ---");
        force dut.key_up = 1'b1;
        repeat (2) @(posedge dut.frame_tick);
        release dut.key_up;
        @(posedge dut.frame_tick);
        if (dut.game_state == 2'd0)
            $display("PASS: Arrow key does not start from IDLE");
        else
            $display("FAIL: Arrow key started game from IDLE (state=%0d)", dut.game_state);

        force dut.key_pause = 1'b1; // key "5"
        repeat (2) @(posedge dut.frame_tick);
        release dut.key_pause;
        @(posedge dut.frame_tick);
        if (dut.game_state == 2'd1)
            $display("PASS: Key 5 starts game from IDLE");
        else
            $display("FAIL: Key 5 did not start game (state=%0d)", dut.game_state);

        // Ensure BEST has a non-zero known value via one forced "eat" event
        force dut.eating_food = 1'b1;
        force dut.hit_body    = 1'b0;
        force dut.frame_cnt   = 4'd14;
        @(posedge dut.frame_tick);
        #60;
        release dut.eating_food;
        release dut.hit_body;
        release dut.frame_cnt;
        if (dut.best_score > 8'd0)
            $display("PASS: BEST updates during play");
        else
            $display("FAIL: BEST did not update");

        reset_counters;
        #(2 * ONE_FRAME);

        $display("--- Phase 3: ST_PLAYING ---");
        $display("Green  : %0d (expect ~1800 head pixels)", green_pixels);
        $display("Red    : %0d (expect >0 food)", red_pixels);
        $display("White  : %0d (expect >0 score)", white_pixels);
        $display("Bad    : %0d (expect 0)", bad_pixels);

        if (green_pixels >= 1700 && green_pixels <= 1900)
            $display("PASS: Head pixel count OK");
        else
            $display("FAIL: Head pixels wrong - got %0d", green_pixels);

        if (red_pixels > 0)
            $display("PASS: Food rendered");
        else
            $display("FAIL: No food pixels");

        if (white_pixels > 0)
            $display("PASS: Score overlay rendered");
        else
            $display("FAIL: No score pixels");

        if (bad_pixels == 0)
            $display("PASS: No pixels outside DE");
        else
            $display("FAIL: %0d pixels outside DE", bad_pixels);

        // ---- Phase 4: Snake movement ----
        // Force frame_cnt -> move fires on next frame_tick (no 15-frame wait).
        // Snake is going UP: head_row must decrease by 1.
        $display("--- Phase 4: Snake movement ---");
        begin : phase3
            reg [4:0] pre_col;
            reg [3:0] pre_row;
            pre_col = dut.head_col;
            pre_row = dut.head_row;
            $display("Pre-move  head: col=%0d row=%0d", pre_col, pre_row);
            force_one_move;
            $display("Post-move head: col=%0d row=%0d", dut.head_col, dut.head_row);
            if (dut.head_row < pre_row || (pre_row == 4'd0 && dut.head_row == 4'd14))
                $display("PASS: Snake moved UP");
            else
                $display("FAIL: Snake did not move UP (row %0d -> %0d)", pre_row, dut.head_row);
            // Count one clean frame to verify pixel output after the move
            reset_counters;
            #(ONE_FRAME);
            if (green_pixels >= 800 && green_pixels <= 1000)
                $display("PASS: Head pixels OK after move");
            else
                $display("FAIL: Head pixels wrong after move - got %0d", green_pixels);
        end

        // ---- Phase 5: U-turn prevention ----
        // Direction is UP. Force key_down=1 (opposite) for one frame, then
        // trigger a move and verify the row still decreased (snake kept going UP).
        $display("--- Phase 5: U-turn prevention ---");
        begin : phase4
            reg [3:0] pre_row4;
            pre_row4 = dut.head_row;
            // Override keypad_scanner outputs to simulate pressing DOWN
            force dut.key_down = 1'b1;
            force dut.key_up   = 1'b0;
            @(posedge dut.frame_tick);  // let one frame_tick see key_down
            #1;
            release dut.key_down;
            release dut.key_up;
            // Now trigger a move
            force_one_move;
            $display("Post-Uturn head: col=%0d row=%0d", dut.head_col, dut.head_row);
            if (dut.head_row < pre_row4 || (pre_row4 == 4'd0 && dut.head_row == 4'd14))
                $display("PASS: U-turn blocked, snake still moving UP");
            else
                $display("FAIL: U-turn NOT blocked (row %0d -> %0d)", pre_row4, dut.head_row);
        end

        // ---- Phase 6: Pause/Resume (key 5) ----
        $display("--- Phase 6: Pause/Resume (key 5) ---");
        begin : phase5
            reg [4:0] pre_col5;
            reg [3:0] pre_row5;
            reg [4:0] paused_col5;
            reg [3:0] paused_row5;

            // Ensure a clean low level first, then create a rising edge
            force dut.key_pause = 1'b0;
            @(posedge dut.frame_tick);

            // Toggle pause ON
            force dut.key_pause = 1'b1;
            @(posedge dut.frame_tick);
            #1;
            release dut.key_pause;

            if (dut.paused)
                $display("PASS: Pause toggled ON");
            else
                $display("FAIL: Pause did not toggle ON");

            // Verify snake is frozen while paused
            pre_col5 = dut.head_col;
            pre_row5 = dut.head_row;
            #(2 * ONE_FRAME);
            paused_col5 = dut.head_col;
            paused_row5 = dut.head_row;
            if (paused_col5 == pre_col5 && paused_row5 == pre_row5)
                $display("PASS: Snake frozen during pause");
            else
                $display("FAIL: Snake moved during pause (%0d,%0d)->(%0d,%0d)",
                         pre_col5, pre_row5, paused_col5, paused_row5);

            // Ensure a clean low level first, then create a rising edge
            force dut.key_pause = 1'b0;
            @(posedge dut.frame_tick);

            // Toggle pause OFF
            force dut.key_pause = 1'b1;
            @(posedge dut.frame_tick);
            #1;
            release dut.key_pause;

            if (!dut.paused)
                $display("PASS: Pause toggled OFF (resume)");
            else
                $display("FAIL: Pause did not toggle OFF");

            // Verify movement resumes
            pre_col5 = dut.head_col;
            pre_row5 = dut.head_row;
            force_one_move;
            if (dut.head_col != pre_col5 || dut.head_row != pre_row5)
                $display("PASS: Snake moves after resume");
            else
                $display("FAIL: Snake still frozen after resume");
        end

        // ---- Phase 7: Restart by D long-press ----
        $display("--- Phase 7: Restart by D long-press ---");
        begin : phase6
            // Short press: should NOT restart
            force dut.key_restart = 1'b1;
            repeat (3) @(posedge dut.frame_tick);
            release dut.key_restart;
            @(posedge dut.frame_tick);
            if (dut.game_state == 2'd1 && dut.restart_latched == 1'b0)
                $display("PASS: Short D press ignored");
            else
                $display("FAIL: Short D press triggered restart (state=%0d)", dut.game_state);

            // Long-press behavior (optimized): pre-load counter near threshold,
            // then hold D for 2 frame ticks to cross the restart trigger point.
            force dut.restart_hold_cnt = 7'd58;
            force dut.key_restart = 1'b1;
            repeat (2) @(posedge dut.frame_tick);
            release dut.key_restart;
            release dut.restart_hold_cnt;
            #100;

            if (dut.game_state == 2'd0)
                $display("PASS: Long D press restarted to ST_IDLE");
            else
                $display("FAIL: Long D press did not restart (state=%0d)", dut.game_state);

            if (dut.score == 8'd0 && dut.snake_len == 7'd3 && dut.paused == 1'b0)
                $display("PASS: Restart reset core game state");
            else
                $display("FAIL: Restart state wrong (score=%0d len=%0d paused=%0d)",
                         dut.score, dut.snake_len, dut.paused);

            // Re-enter PLAYING quickly with key 5 so following phases remain valid
            force dut.key_pause = 1'b1;
            @(posedge dut.frame_tick);
            #1;
            release dut.key_pause;
            @(posedge dut.frame_tick);
            if (dut.game_state == 2'd1)
                $display("PASS: Re-entered ST_PLAYING after restart");
            else
                $display("FAIL: Could not re-enter ST_PLAYING (state=%0d)", dut.game_state);

            if (dut.score == 8'd0 && dut.best_score > 8'd0)
                $display("PASS: New game resets SCORE and keeps BEST");
            else
                $display("FAIL: SCORE/BEST after restart-start wrong (score=%0d best=%0d)",
                         dut.score, dut.best_score);
        end

        // ---- Phase 8: Self-collision -> Game Over ----
        // hit_body is only evaluated when frame_tick AND frame_cnt==move_speed-1.
        // Force both so the collision check fires on the very next frame_tick.
        $display("--- Phase 8: Self-collision -> Game Over ---");
        force dut.score = 8'd7;
        force dut.hit_body  = 1'b1;
        force dut.frame_cnt = 4'd14;
        @(posedge dut.frame_tick);
        #60;
        release dut.score;
        release dut.hit_body;
        release dut.frame_cnt;
        #100;
        if (dut.game_state == 2'd2)
            $display("PASS: Transitioned to ST_GAME_OVER");
        else
            $display("FAIL: game_state=%0d (expected 2=ST_GAME_OVER)", dut.game_state);

        if (dut.last_score == 8'd7)
            $display("PASS: LAST score latched on game over");
        else
            $display("FAIL: LAST score wrong (last=%0d expected=7)", dut.last_score);

        // ---- Phase 9: Game Over visuals ----
        // anyred_pixels covers both flash states (bright R=11111 and dark R=00110).
        // Expect: anyred > 0, GAME OVER text (white > 0), no green, no bad pixels.
        reset_counters;
        #(2 * ONE_FRAME);
        $display("--- Phase 9: Game Over visuals ---");
        $display("AnyRed : %0d (expect >0 flash bg)", anyred_pixels);
        $display("White  : %0d (expect >0 GAME OVER text)", white_pixels);
        $display("Green  : %0d (expect 0)", green_pixels);
        $display("Bad    : %0d (expect 0)", bad_pixels);

        if (anyred_pixels > 0)
            $display("PASS: Red flash background visible");
        else
            $display("FAIL: No red background in Game Over");

        if (white_pixels > 0)
            $display("PASS: GAME OVER text visible");
        else
            $display("FAIL: No GAME OVER text pixels");

        if (green_pixels == 0)
            $display("PASS: No snake pixels in Game Over");
        else
            $display("FAIL: Unexpected green in Game Over: %0d", green_pixels);

        if (bad_pixels == 0)
            $display("PASS: No pixels outside DE in Game Over");
        else
            $display("FAIL: %0d pixels outside DE in Game Over", bad_pixels);

        // ---- Phase 10: Reset from Game Over -> ST_IDLE ----
        $display("--- Phase 10: Reset from Game Over ---");
        reset_btn = 1'b0;  // S1 active-low: assert reset
        #200;
        reset_btn = 1'b1;
        reset_counters;
        #(2 * ONE_FRAME);
        $display("State  : %0d (expect 0=ST_IDLE)", dut.game_state);
        $display("White  : %0d (expect >0 title screen)", white_pixels);
        $display("Green  : %0d (expect 0)", green_pixels);

        if (dut.game_state == 2'd0)
            $display("PASS: Back to ST_IDLE after reset");
        else
            $display("FAIL: game_state=%0d (expected 0=ST_IDLE)", dut.game_state);

        if (white_pixels > 0)
            $display("PASS: Title screen visible after reset");
        else
            $display("FAIL: No title text after reset");

        if (green_pixels == 0)
            $display("PASS: No game pixels after reset");
        else
            $display("FAIL: Unexpected green after reset: %0d", green_pixels);

        $display("=== Done ===");
        $finish;
    end

endmodule
